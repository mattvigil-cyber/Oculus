import Foundation
import Network

/// A loopback-only static file server.
///
/// The piece needs a secure origin — `getUserMedia` is unreachable from `file://`,
/// and a custom URL scheme is not "potentially trustworthy" either. 127.0.0.1 is,
/// so the cheapest honest answer is to actually serve the folder.
final class LocalServer {

    enum Failure: Error { case badPort, bindFailed }

    private let root: URL
    private let queue = DispatchQueue(label: "com.mattvigil.oculus.server")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Binds the first free port at or after `preferred`.
    func start(preferred: UInt16, attempts: Int = 20) throws {
        for offset in 0..<attempts {
            let candidate = preferred &+ UInt16(offset)
            do {
                try bind(candidate)
                port = candidate
                return
            } catch {
                continue
            }
        }
        throw Failure.bindFailed
    }

    private func bind(_ p: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: p) else { throw Failure.badPort }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Loopback only. This should never be reachable from the network.
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)

        let l = try NWListener(using: params)

        // NWListener reports bind failures asynchronously, so wait for it to
        // actually come up before claiming the port.
        let ready = DispatchSemaphore(value: 0)
        var failed = false
        l.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed, .cancelled:
                failed = true
                ready.signal()
            default:
                break
            }
        }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.start(queue: queue)

        if ready.wait(timeout: .now() + 3) == .timedOut || failed {
            l.cancel()
            throw Failure.bindFailed
        }
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        read(conn, buffer: Data())
    }

    private func read(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] chunk, _, done, error in
            guard let self else { conn.cancel(); return }

            var buf = buffer
            if let chunk { buf.append(chunk) }

            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self)
                self.respond(head, on: conn)
                return
            }
            // A request head this large is not a request we serve.
            if error != nil || done || buf.count > 64 * 1024 {
                conn.cancel()
                return
            }
            self.read(conn, buffer: buf)
        }
    }

    private func respond(_ head: String, on conn: NWConnection) {
        guard
            let requestLine = head.components(separatedBy: "\r\n").first,
            case let fields = requestLine.split(separator: " "),
            fields.count >= 2,
            fields[0] == "GET" || fields[0] == "HEAD"
        else {
            send(status: "400 Bad Request", body: Data("bad request".utf8), type: "text/plain", on: conn)
            return
        }

        let target = String(fields[1])
        let pathPart = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        let decoded = pathPart.removingPercentEncoding ?? pathPart

        guard let file = resolve(decoded) else {
            send(status: "404 Not Found", body: Data("not found".utf8), type: "text/plain", on: conn)
            return
        }

        guard let body = try? Data(contentsOf: file) else {
            send(status: "404 Not Found", body: Data("not found".utf8), type: "text/plain", on: conn)
            return
        }

        let ext = file.pathExtension.lowercased()
        // The piece itself is re-read every load so edits show up on reload; the
        // vendored detector never changes and is worth caching in the web process.
        let cache = (ext == "html") ? "no-store" : "public, max-age=31536000, immutable"
        send(status: "200 OK", body: body, type: Self.mime(ext), cache: cache,
             headOnly: fields[0] == "HEAD", on: conn)
    }

    /// Maps a URL path onto a file inside `root`, refusing anything that escapes it.
    private func resolve(_ path: String) -> URL? {
        var rel = path
        while rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { rel = "i-see-you.html" }

        let candidate = root.appendingPathComponent(rel).standardizedFileURL
        let rootPath = root.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else { return nil }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        return candidate
    }

    private func send(status: String, body: Data, type: String,
                      cache: String = "no-store", headOnly: Bool = false,
                      on conn: NWConnection) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(type)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: \(cache)\r\n"
        header += "Connection: close\r\n\r\n"

        var out = Data(header.utf8)
        if !headOnly { out.append(body) }
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func mime(_ ext: String) -> String {
        switch ext {
        case "html", "htm":  return "text/html; charset=utf-8"
        case "js", "mjs":    return "text/javascript; charset=utf-8"
        case "css":          return "text/css; charset=utf-8"
        case "json":         return "application/json; charset=utf-8"
        // Must be exact, or WebAssembly.instantiateStreaming refuses the module.
        case "wasm":         return "application/wasm"
        case "tflite", "bin": return "application/octet-stream"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "svg":          return "image/svg+xml"
        case "woff2":        return "font/woff2"
        default:             return "application/octet-stream"
        }
    }
}
