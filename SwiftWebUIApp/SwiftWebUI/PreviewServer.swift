import Foundation
import Network
import SwiftWebUICore

/// Serves the current preview over HTTP on the loopback interface, so it can be opened in any browser.
/// Browsers poll for changes and update in place, the same way the built-in preview does.
final class PreviewServer: @unchecked Sendable {
    private let lock = NSLock()
    private var output = RenderOutput.empty
    private var version = 1
    private var listener: NWListener?
    private(set) var port: UInt16?
    /// Called on the main queue when the server starts listening, with its port.
    var onReady: (@Sendable (UInt16) -> Void)?

    static let preferredPort: UInt16 = 4321

    func start() {
        start(on: NWEndpoint.Port(rawValue: Self.preferredPort))
    }

    private func start(on port: NWEndpoint.Port?) {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback // never reachable from other machines
        let listener: NWListener
        do { listener = try port.map { try NWListener(using: params, on: $0) } ?? NWListener(using: params) }
        catch { if port != nil { start(on: nil) }; return }
        listener.newConnectionHandler = { [weak self] in self?.handle($0) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            switch state {
            case .ready:
                if let p = listener.port?.rawValue {
                    self.lock.lock(); self.port = p; self.lock.unlock()
                    DispatchQueue.main.async { self.onReady?(p) }
                }
            case .failed:
                listener.cancel()
                if port != nil { self.start(on: nil) } // preferred port is taken: let the system choose
            default: break
            }
        }
        self.listener = listener
        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() { listener?.cancel(); listener = nil }

    func update(_ new: RenderOutput) {
        lock.lock(); output = new; version += 1; lock.unlock()
    }

    // MARK: HTTP

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data else { connection.cancel(); return }
            let response = self.respond(to: String(decoding: data, as: UTF8.self))
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func respond(to request: String) -> Data {
        let lines = request.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0] == "GET" else { return http(405, "text/plain", "Method not allowed") }
        // Only answer requests addressed to localhost, so another site can't read the preview via DNS rebinding.
        let host = lines.first { $0.lowercased().hasPrefix("host:") }?.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard let port, host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else { return http(403, "text/plain", "Forbidden") }
        let path = String(parts[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        lock.lock()
        let (current, v) = (output, version)
        lock.unlock()
        switch path {
        case "/":
            return http(200, "text/html; charset=utf-8",
                        PageTemplate.document(current, title: "SwiftWebUI Preview", livePath: "/__swui/render", liveVersion: v))
        case "/__swui/render":
            let body: [String: Any] = ["version": v, "html": current.html,
                                       "states": (try? JSONSerialization.jsonObject(with: Data(current.statesJSON.utf8))) ?? [:]]
            let json = (try? JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8)
            return http(200, "application/json", String(decoding: json, as: UTF8.self))
        default:
            return http(404, "text/plain", "Not found")
        }
    }

    private func http(_ status: Int, _ type: String, _ body: String) -> Data {
        let reason = [200: "OK", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"][status] ?? ""
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(bytes.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + bytes
    }
}
