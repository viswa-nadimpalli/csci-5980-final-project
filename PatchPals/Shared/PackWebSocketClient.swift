import Foundation

/// Connects to /ws/packs/{packID} and delivers decoded events on the main actor.
/// Only one pack is subscribed at a time — call connect() to switch packs.
@MainActor
final class PackWebSocketClient: ObservableObject {
    private var task: URLSessionWebSocketTask?
    private var connectedPackID: String?

    /// Called on the main actor whenever a valid event arrives.
    var onEvent: ((PackWebSocketEvent) -> Void)?

    private let wsBaseURL = URL(string: "wss://api.18-191-85-231.nip.io")!

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
            Task { @MainActor [weak self] in
                guard let self, self.task != nil else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let event = try? JSONDecoder().decode(PackWebSocketEvent.self, from: data) {
                        self.onEvent?(event)
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
