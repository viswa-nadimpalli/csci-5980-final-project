import Foundation
import OSLog

/// Connects to /ws/packs/{packID} and delivers decoded events on the main actor.
/// Only one pack is subscribed at a time — call connect() to switch packs.
@MainActor
final class PackWebSocketClient: ObservableObject {
    private var task: URLSessionWebSocketTask?
    private var connectedPackID: String?

    /// Called on the main actor whenever a valid event arrives.
    var onEvent: ((PackWebSocketEvent) -> Void)?

    private let wsBaseURL = URL(string: "wss://api.18-191-85-231.nip.io")!
    private let signposter = OSSignposter(subsystem: "com.patchpals.websocket", category: "PackWebSocketClient")
    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func connect(packID: String) {
        guard connectedPackID != packID else { return }
        disconnect()
        connectedPackID = packID
        let url = wsBaseURL.appendingPathComponent("ws/packs/\(packID)")
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        connectedPackID = nil
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            // Capture receive time before the actor hop so it reflects actual network arrival.
            let receivedAt = Date()
            Task { @MainActor [weak self] in
                guard let self, self.task != nil else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let event = try? JSONDecoder().decode(PackWebSocketEvent.self, from: data) {
                        let serverTime = self.iso8601.date(from: event.serverTimestamp)
                        let latencyMs = serverTime.map { receivedAt.timeIntervalSince($0) * 1000 } ?? -1
                        let state = self.signposter.beginInterval(
                            "WebSocket event received",
                            id: .exclusive,
                            "pack: \(event.packId), server_to_client_ms: \(Int(latencyMs))"
                        )
                        self.onEvent?(event)
                        self.signposter.endInterval("WebSocket event received", state)
                    }
                    self.receiveLoop()
                case .failure:
                    // Connection closed or lost — no auto-reconnect for MVP
                    self.task = nil
                    self.connectedPackID = nil
                }
            }
        }
    }
}
