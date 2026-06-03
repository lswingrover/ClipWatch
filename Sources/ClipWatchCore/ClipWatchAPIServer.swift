/// ClipWatchAPIServer.swift — Localhost HTTP API for ClipWatch headless/AI administration
///
/// Port suite: MacWatch=57820  NetWatch=57821  ClipWatch=57822
///
/// Endpoints:
///   GET /ping              → {"pong":true, "locked":bool, ...}
///   GET /health            → db path, clip count, lock state, db size
///   GET /lock              → lock ClipWatch immediately; returns {"locked":true}
///   GET /clips?limit=N     → recent N clips (locked: 423)
///   GET /search?q=TEXT     → FTS5 full-text search (locked: 423)
///   GET /clip?id=N         → single clip by rowid (locked: 423)
///   GET /pin?id=N          → toggle pin (locked: 423)
///   GET /delete?id=N       → delete clip (locked: 423)
///   GET /sensitive         → clips flagged sensitive (locked: 423)
///
/// Security: binds 127.0.0.1 only. Unlock requires Touch ID from the UI —
/// the API intentionally cannot unlock (biometrics need user interaction).

import Foundation
import Network

// MARK: - Payload types

public struct CWAPIHealthPayload: Codable {
    let running:           Bool
    let locked:            Bool
    let secureModeEnabled: Bool
    let clipCount:         Int
    let dbPath:            String
    let dbSizeKB:          Int64
    let port:              UInt16

    public init(running: Bool, locked: Bool, secureModeEnabled: Bool,
                clipCount: Int, dbPath: String, dbSizeKB: Int64, port: UInt16) {
        self.running           = running
        self.locked            = locked
        self.secureModeEnabled = secureModeEnabled
        self.clipCount         = clipCount
        self.dbPath            = dbPath
        self.dbSizeKB          = dbSizeKB
        self.port              = port
    }
}

public struct CWAPIClip: Codable {
    let id:        Int64
    let content:   String
    let ts:        String
    let pinned:    Bool
    let source:    String?
    let sensitive: Bool
    let preview:   String

    public init(id: Int64, content: String, ts: String, pinned: Bool,
                source: String? = nil, sensitive: Bool, preview: String) {
        self.id = id; self.content = content; self.ts = ts
        self.pinned = pinned; self.source = source
        self.sensitive = sensitive; self.preview = preview
    }
}

public struct CWAPISearchResult: Codable {
    let query: String; let count: Int; let results: [CWAPIClip]
    public init(query: String, count: Int, results: [CWAPIClip]) {
        self.query = query; self.count = count; self.results = results
    }
}

public struct CWAPIMutationResult: Codable {
    let success: Bool; let id: Int64; let action: String
    public init(success: Bool, id: Int64, action: String) {
        self.success = success; self.id = id; self.action = action
    }
}

// MARK: - Server

public final class ClipWatchAPIServer {
    private var listener:    NWListener?
    private var connections: [NWConnection] = []
    public private(set) var isRunning: Bool = false
    public var port: UInt16 = 57_822

    public func start() {
        guard !isRunning else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            print("[ClipWatchAPI] Failed to create listener: \(error)"); return
        }
        listener?.newConnectionHandler = { [weak self] conn in self?.acceptConnection(conn) }
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                print("[ClipWatchAPI] Listening on 127.0.0.1:\(self?.port ?? 0)")
            case .failed(let err):
                self?.isRunning = false
                print("[ClipWatchAPI] Listener failed: \(err)")
            default: break
            }
        }
        listener?.start(queue: DispatchQueue(label: "clipwatch.api.listener", qos: .utility))
    }

    public func stop() {
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections.removeAll()
        isRunning = false
    }

    private func acceptConnection(_ connection: NWConnection) {
        DispatchQueue.main.async { self.connections.append(connection) }
        connection.start(queue: DispatchQueue(label: "clipwatch.api.conn", qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                DispatchQueue.main.async { self?.connections.removeAll { $0 === connection } }
                return
            }
            DispatchQueue.main.async { self?.handleRequest(request, connection: connection) }
        }
    }

    private func handleRequest(_ raw: String, connection: NWConnection) {
        let firstLine = raw.components(separatedBy: "\r\n").first ?? ""
        let parts     = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendResponse(connection: connection, status: 405, body: #"{"error":"Method Not Allowed"}"#)
            return
        }
        let fullPath = parts[1]
        let path     = fullPath.components(separatedBy: "?").first ?? fullPath
        let query    = fullPath.contains("?") ? fullPath.components(separatedBy: "?")[1] : ""
        let (status, body) = route(path: path, query: query)
        sendResponse(connection: connection, status: status, body: body)
        connections.removeAll { $0 === connection }
    }

    private func route(path: String, query: String) -> (Int, String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting     = .prettyPrinted

        let isLocked = Prefs.isSecureModeEnabled() && LockManager.shared.isLocked

        switch path {
        case "/ping":
            return (200, """
                {"pong":true,"app":"ClipWatch","port":57822,\
                "locked":\(isLocked),"secureModeEnabled":\(Prefs.isSecureModeEnabled())}
                """)

        case "/", "/health":
            return handleHealth(encoder: enc, isLocked: isLocked)

        case "/lock":
            LockManager.shared.lock()
            return (200, #"{"locked":true,"action":"locked"}"#)

        case "/clips", "/search", "/clip", "/pin", "/delete", "/sensitive":
            if isLocked {
                return (423, #"{"error":"ClipWatch is locked","hint":"Unlock via the menu bar or Touch ID"}"#)
            }
            LockManager.shared.touchActivity()
            return routeData(path: path, query: query, encoder: enc)

        default:
            return (404, """
                {"error":"Not found","endpoints":["/ping","/health","/lock",\
                "/clips","/search?q=X","/clip?id=N","/pin?id=N","/delete?id=N","/sensitive"]}
                """)
        }
    }

    private func routeData(path: String, query: String, encoder: JSONEncoder) -> (Int, String) {
        switch path {
        case "/clips":
            let limit = Int(queryParam("limit", from: query)) ?? 50
            return encode(ClipStore.shared.recent(limit: min(limit, 500)).map(apiClip), encoder: encoder)

        case "/search":
            let q = queryParam("q", from: query)
            guard !q.isEmpty else { return (400, #"{"error":"Missing ?q= parameter"}"#) }
            let limit   = Int(queryParam("limit", from: query)) ?? 200
            let results = ClipStore.shared.search(query: q, limit: min(limit, 500))
            return encode(CWAPISearchResult(query: q, count: results.count,
                                             results: results.map(apiClip)), encoder: encoder)

        case "/clip":
            let id = Int64(queryParam("id", from: query)) ?? -1
            guard id > 0 else { return (400, #"{"error":"Missing or invalid ?id= parameter"}"#) }
            guard let clip = ClipStore.shared.recent(limit: 50_000).first(where: { $0.id == id })
            else { return (404, #"{"error":"Clip not found"}"#) }
            return encode(apiClip(clip), encoder: encoder)

        case "/pin":
            let id = Int64(queryParam("id", from: query)) ?? -1
            guard id > 0 else { return (400, #"{"error":"Missing or invalid ?id= parameter"}"#) }
            ClipStore.shared.togglePin(id: id)
            return encode(CWAPIMutationResult(success: true, id: id, action: "pin_toggled"), encoder: encoder)

        case "/delete":
            let id = Int64(queryParam("id", from: query)) ?? -1
            guard id > 0 else { return (400, #"{"error":"Missing or invalid ?id= parameter"}"#) }
            ClipStore.shared.delete(id: id)
            return encode(CWAPIMutationResult(success: true, id: id, action: "deleted"), encoder: encoder)

        case "/sensitive":
            let all = ClipStore.shared.recent(limit: 50_000)
            return encode(all.filter { $0.sensitive }.map(apiClip), encoder: encoder)

        default:
            return (404, #"{"error":"Not found"}"#)
        }
    }

    private func handleHealth(encoder: JSONEncoder, isLocked: Bool) -> (Int, String) {
        let dbPath = (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ClipWatch/clips.db").path) ?? "unknown"
        let dbSize  = (try? FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int64) ?? 0
        let count   = ClipStore.shared.recent(limit: 1_000_000).count
        let payload = CWAPIHealthPayload(
            running:           true,
            locked:            isLocked,
            secureModeEnabled: Prefs.isSecureModeEnabled(),
            clipCount:         count,
            dbPath:            dbPath,
            dbSizeKB:          dbSize / 1024,
            port:              port
        )
        return encode(payload, encoder: encoder)
    }

    private func apiClip(_ clip: ClipStore.Clip) -> CWAPIClip {
        let preview = clip.content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .prefix(120)
        return CWAPIClip(id: clip.id, content: clip.content,
                         ts: ISO8601DateFormatter().string(from: clip.ts),
                         pinned: clip.pinned, source: clip.source,
                         sensitive: clip.sensitive, preview: String(preview))
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText: String = {
            switch status {
            case 200: return "OK"; case 400: return "Bad Request"
            case 404: return "Not Found"; case 405: return "Method Not Allowed"
            case 423: return "Locked"; default: return "Error"
            }
        }()
        let response = "HTTP/1.1 \(status) \(statusText)\r\n" +
                       "Content-Type: application/json\r\n" +
                       "Content-Length: \(body.utf8.count)\r\n" +
                       "Access-Control-Allow-Origin: *\r\n" +
                       "Connection: close\r\n\r\n" + body
        guard let data = response.data(using: .utf8) else { connection.cancel(); return }
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func encode<T: Encodable>(_ value: T, encoder: JSONEncoder) -> (Int, String) {
        do {
            let data = try encoder.encode(value)
            return (200, String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            return (500, #"{"error":"Encoding failed"}"#)
        }
    }

    private func queryParam(_ key: String, from query: String) -> String {
        for pair in query.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2, kv[0] == key {
                return kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return ""
    }

    public init(port: UInt16 = 57_822) { self.port = port }
}
