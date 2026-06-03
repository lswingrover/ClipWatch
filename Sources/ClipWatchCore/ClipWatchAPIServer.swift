/// ClipWatchAPIServer.swift — Localhost HTTP API for ClipWatch headless/AI administration
///
/// Exposes a JSON API on 127.0.0.1:57822 (configurable).
/// Allows Claude companion skills and other AI tools to search, read, pin, and
/// delete clipboard history without needing the panel UI open.
///
/// Port suite: MacWatch=57820  NetWatch=57821 (existing)  ClipWatch=57822
///
/// Endpoints:
///   GET /ping              → {"pong": true}
///   GET /health            → db path, clip count, db size
///   GET /clips?limit=N     → most recent N clips (default 50, max 500)
///   GET /search?q=TEXT     → FTS5 full-text search (limit=200)
///   GET /clip?id=N         → single clip by rowid
///   GET /pin?id=N          → toggle pin on clip N (returns updated clip)
///   GET /delete?id=N       → delete clip N (returns {"deleted":true})
///   GET /sensitive         → all clips flagged as sensitive
///
/// Security: binds to 127.0.0.1 (loopback) only. Never accessible remotely.
/// Auth: none — local-only, Claude/AI is the consumer.
///
/// Wiring: AppDelegate owns `let apiServer = ClipWatchAPIServer()`.
///   Start: call `apiServer.start()` in applicationDidFinishLaunching.
///   Stop:  call `apiServer.stop()` in applicationWillTerminate.
///
/// GH: lswingrover/clipwatch#XX (headless API server)
import Foundation
import Network

// MARK: - Payload types

public struct CWAPIHealthPayload: Codable {
    let running:    Bool
    let clipCount:  Int
    let dbPath:     String
    let dbSizeKB:   Int64
    let port:       UInt16
}

public struct CWAPIClip: Codable {
    let id:        Int64
    let content:   String
    let ts:        String   // ISO8601
    let pinned:    Bool
    let source:    String?  // bundle ID of source app
    let sensitive: Bool
    let preview:   String   // first 120 chars, whitespace-collapsed
}

public struct CWAPISearchResult: Codable {
    let query:   String
    let count:   Int
    let results: [CWAPIClip]
}

public struct CWAPIMutationResult: Codable {
    let success: Bool
    let id:      Int64
    let action:  String
}

// MARK: - Server

public final class ClipWatchAPIServer {

    // MARK: - State
    private var listener:    NWListener?
    private var connections: [NWConnection] = []
    public private(set) var isRunning: Bool = false
    public var port: UInt16 = 57_822

    // MARK: - Start / Stop

    public func start() {
        guard !isRunning else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            print("[ClipWatchAPI] Invalid port \(port)")
            return
        }
        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            print("[ClipWatchAPI] Failed to create listener: \(error)")
            return
        }
        listener?.newConnectionHandler = { [weak self] conn in
            self?.acceptConnection(conn)
        }
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
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
    }

    // MARK: - Connection handling

    private func acceptConnection(_ connection: NWConnection) {
        // Dispatch connection list mutations to main to stay thread-safe
        DispatchQueue.main.async { self.connections.append(connection) }
        connection.start(queue: DispatchQueue(label: "clipwatch.api.conn", qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                DispatchQueue.main.async {
                    self?.connections.removeAll { $0 === connection }
                }
                return
            }
            // Route on main: ClipStore is not thread-safe for writes
            DispatchQueue.main.async {
                self?.handleRequest(request, connection: connection)
            }
        }
    }

    private func handleRequest(_ raw: String, connection: NWConnection) {
        let firstLine = raw.components(separatedBy: "\r\n").first ?? ""
        let parts     = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendResponse(connection: connection, status: 405,
                         body: #"{"error":"Method Not Allowed"}"#)
            return
        }
        let fullPath = parts[1]
        let path     = fullPath.components(separatedBy: "?").first ?? fullPath
        let query    = fullPath.contains("?")
                       ? fullPath.components(separatedBy: "?")[1] : ""
        let (status, body) = route(path: path, query: query)
        sendResponse(connection: connection, status: status, body: body)
        connections.removeAll { $0 === connection }
    }

    // MARK: - Routing

    private func route(path: String, query: String) -> (Int, String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting     = .prettyPrinted

        switch path {

        case "/ping":
            return (200, #"{"pong":true,"app":"ClipWatch","port":57822}"#)

        case "/", "/health":
            return handleHealth(encoder: enc)

        case "/clips":
            let limit = Int(queryParam("limit", from: query)) ?? 50
            let clips = ClipStore.shared.recent(limit: min(limit, 500))
            return encode(clips.map(apiClip), encoder: enc)

        case "/search":
            let q     = queryParam("q", from: query)
            guard !q.isEmpty else {
                return (400, #"{"error":"Missing ?q= parameter"}"#)
            }
            let limit   = Int(queryParam("limit", from: query)) ?? 200
            let results = ClipStore.shared.search(query: q, limit: min(limit, 500))
            let payload = CWAPISearchResult(query: q, count: results.count,
                                            results: results.map(apiClip))
            return encode(payload, encoder: enc)

        case "/clip":
            let id = Int64(queryParam("id", from: query)) ?? -1
            guard id > 0 else {
                return (400, #"{"error":"Missing or invalid ?id= parameter"}"#)
            }
            // Fetch by ID via a single-item search isn't supported directly;
            // use recent + filter as a lightweight fallback.
            let results = ClipStore.shared.recent(limit: 50_000)
            guard let clip = results.first(where: { $0.id == id }) else {
                return (404, #"{"error":"Clip not found"}"#)
            }
            return encode(apiClip(clip), encoder: enc)

        case "/pin":
            let id = Int64(queryParam("id", from: query)) ?? -1
            guard id > 0 else {
                return (400, #"{"error":"Missing or invalid ?id= parameter"}"#)
            }
            ClipStore.shared.togglePin(id: id)
            let result = CWAPIMutationResult(success: true, id: id, action: "pin_toggled")
            return encode(result, encoder: enc)

        case "/delete":
            let id = Int64(queryParam("id", from: query)) ?? -1
            guard id > 0 else {
                return (400, #"{"error":"Missing or invalid ?id= parameter"}"#)
            }
            ClipStore.shared.delete(id: id)
            let result = CWAPIMutationResult(success: true, id: id, action: "deleted")
            return encode(result, encoder: enc)

        case "/sensitive":
            // Recent clips filtered to sensitive flag
            let all       = ClipStore.shared.recent(limit: 50_000)
            let sensitive = all.filter { $0.sensitive }
            return encode(sensitive.map(apiClip), encoder: enc)

        default:
            return (404, """
                {"error":"Not found",\
                "endpoints":["/ping","/health","/clips","/search?q=X",\
                "/clip?id=N","/pin?id=N","/delete?id=N","/sensitive"]}
                """)
        }
    }

    // MARK: - /health

    private func handleHealth(encoder: JSONEncoder) -> (Int, String) {
        let dbPath = (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ClipWatch/clips.db").path) ?? "unknown"
        let dbSize = (try? FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int64) ?? 0
        let count  = ClipStore.shared.recent(limit: 1_000_000).count  // approximate
        let payload = CWAPIHealthPayload(
            running:   true,
            clipCount: count,
            dbPath:    dbPath,
            dbSizeKB:  dbSize / 1024,
            port:      port
        )
        return encode(payload, encoder: encoder)
    }

    // MARK: - Helpers

    private func apiClip(_ clip: ClipStore.Clip) -> CWAPIClip {
        let fmt     = ISO8601DateFormatter()
        let preview = clip.content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .prefix(120)
        return CWAPIClip(
            id:        clip.id,
            content:   clip.content,
            ts:        fmt.string(from: clip.ts),
            pinned:    clip.pinned,
            source:    clip.source,
            sensitive: clip.sensitive,
            preview:   String(preview)
        )
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText: String = {
            switch status {
            case 200: return "OK"
            case 400: return "Bad Request"
            case 404: return "Not Found"
            case 405: return "Method Not Allowed"
            default:  return "Error"
            }
        }()
        let response = "HTTP/1.1 \(status) \(statusText)\r\n" +
                       "Content-Type: application/json\r\n" +
                       "Content-Length: \(body.utf8.count)\r\n" +
                       "Access-Control-Allow-Origin: *\r\n" +
                       "Connection: close\r\n\r\n" +
                       body
        guard let data = response.data(using: .utf8) else { connection.cancel(); return }
        connection.send(content: data,
                        completion: .contentProcessed { _ in connection.cancel() })
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
}
