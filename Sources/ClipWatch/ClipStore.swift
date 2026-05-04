import Foundation
import SQLite3

// MARK: - ClipStore
//
// Persistent store for clipboard history. All operations are synchronous and
// called from the main thread (ClipboardMonitor and the UI both run there).
//
// Storage path: ~/Library/Application Support/ClipWatch/clips.db
//
// Schema overview:
//   clips      — canonical table: id, content TEXT, ts INTEGER (unix), pinned INTEGER, source TEXT
//   clips_fts  — FTS5 virtual table, content-backed by clips, kept in sync via triggers
//
// FTS5 ships with the macOS system libsqlite3. No extra installation.
// Prefix search is enabled by wrapping the query term in quotes and appending '*':
//   e.g. searching "hel" becomes `"hel"*` which matches "hello", "help", etc.
//
// SQLITE_TRANSIENT (-1 cast to destructor type) tells SQLite to copy the string
// immediately. Without it, SQLite holds a pointer to Swift-managed memory that
// may be freed before SQLite uses it — a hard-to-reproduce crash.

final class ClipStore {
    static let shared = ClipStore()

    struct Clip {
        let id: Int64
        let content: String
        let ts: Date
        let pinned: Bool
        let source: String?  // bundle ID of the app that owned the clipboard at copy time
    }

    private var db: OpaquePointer?
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        openDatabase()
        createSchema()
        pruneOld()
    }

    // MARK: - Setup

    private func openDatabase() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipWatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let path = appSupport.appendingPathComponent("clips.db").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            print("ClipStore: failed to open database at \(path)")
            return
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    private func createSchema() {
        // clips_fts is a "content table" FTS5 index: it stores no data itself,
        // instead reading from `clips` on demand. The triggers keep the index
        // in sync with inserts, deletes, and updates to the canonical table.
        // Dropping and recreating clips without rebuilding clips_fts will cause
        // stale results — if you ever do a schema migration that touches clips,
        // run `INSERT INTO clips_fts(clips_fts) VALUES('rebuild')` afterward.
        let sql = """
        CREATE TABLE IF NOT EXISTS clips (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT    NOT NULL,
            ts      INTEGER NOT NULL,
            pinned  INTEGER NOT NULL DEFAULT 0,
            source  TEXT
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS clips_fts
            USING fts5(content, content='clips', content_rowid='id');
        CREATE TRIGGER IF NOT EXISTS clips_ai AFTER INSERT ON clips BEGIN
            INSERT INTO clips_fts(rowid, content) VALUES (new.id, new.content);
        END;
        CREATE TRIGGER IF NOT EXISTS clips_ad AFTER DELETE ON clips BEGIN
            INSERT INTO clips_fts(clips_fts, rowid, content) VALUES('delete', old.id, old.content);
        END;
        CREATE TRIGGER IF NOT EXISTS clips_au AFTER UPDATE ON clips BEGIN
            INSERT INTO clips_fts(clips_fts, rowid, content) VALUES('delete', old.id, old.content);
            INSERT INTO clips_fts(rowid, content) VALUES (new.id, new.content);
        END;
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Write

    func insert(content: String, source: String?) {
        // Exclusion check
        let defaults = UserDefaults.standard
        var excluded = defaults.stringArray(forKey: Prefs.excludedApps) ?? []
        if excluded.isEmpty { excluded = Prefs.defaultExcludedApps }
        if let source, excluded.contains(source) { return }

        // Deduplicate: skip if identical to the most recent clip
        if let last = recent(limit: 1).first, last.content == content { return }

        let sql = "INSERT INTO clips (content, ts, source) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(Date().timeIntervalSince1970))
        if let source {
            sqlite3_bind_text(stmt, 3, source, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_step(stmt)
        pruneCount()
    }

    func togglePin(id: Int64) {
        exec("UPDATE clips SET pinned = CASE WHEN pinned=0 THEN 1 ELSE 0 END WHERE id=?", id)
    }

    func delete(id: Int64) {
        exec("DELETE FROM clips WHERE id=?", id)
    }

    // MARK: - Read

    func recent(limit: Int) -> [Clip] {
        let sql = """
        SELECT id, content, ts, pinned, source FROM clips
        ORDER BY pinned DESC, ts DESC LIMIT ?
        """
        return query(sql, bindings: [.int(Int64(limit))])
    }

    func search(query queryStr: String, limit: Int = 200) -> [Clip] {
        guard !queryStr.isEmpty else { return recent(limit: limit) }

        // Escape FTS5 special characters, then add prefix wildcard
        let escaped = queryStr
            .replacingOccurrences(of: "\"", with: "\"\"")
        let ftsQuery = "\"\(escaped)\"*"

        let sql = """
        SELECT c.id, c.content, c.ts, c.pinned, c.source
        FROM clips_fts f JOIN clips c ON c.id = f.rowid
        WHERE clips_fts MATCH ?
        ORDER BY c.pinned DESC, rank
        LIMIT ?
        """
        return query(sql, bindings: [.text(ftsQuery), .int(Int64(limit))])
    }

    // MARK: - Pruning

    private func pruneOld() {
        let days = UserDefaults.standard.integer(forKey: Prefs.retentionDays)
        let cutoffDays = days > 0 ? days : 365
        let cutoff = Int64(Date().timeIntervalSince1970) - Int64(cutoffDays * 86400)
        exec("DELETE FROM clips WHERE ts < ? AND pinned = 0", cutoff)
    }

    private func pruneCount() {
        // Keep at most 50 000 unpinned clips
        let sql = """
        DELETE FROM clips WHERE pinned = 0 AND id NOT IN (
            SELECT id FROM clips WHERE pinned = 0 ORDER BY ts DESC LIMIT 50000
        )
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Helpers

    private enum Binding { case text(String); case int(Int64) }

    private func query(_ sql: String, bindings: [Binding] = []) -> [Clip] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        for (i, b) in bindings.enumerated() {
            switch b {
            case .text(let s): sqlite3_bind_text(stmt, Int32(i + 1), s, -1, SQLITE_TRANSIENT)
            case .int(let n):  sqlite3_bind_int64(stmt, Int32(i + 1), n)
            }
        }
        var clips: [Clip] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id      = sqlite3_column_int64(stmt, 0)
            let content = String(cString: sqlite3_column_text(stmt, 1))
            let ts      = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)))
            let pinned  = sqlite3_column_int(stmt, 3) != 0
            let source  = sqlite3_column_type(stmt, 4) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 4)) : nil
            clips.append(Clip(id: id, content: content, ts: ts, pinned: pinned, source: source))
        }
        return clips
    }

    private func exec(_ sql: String, _ value: Int64) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(stmt, 1, value)
        sqlite3_step(stmt)
    }
}
