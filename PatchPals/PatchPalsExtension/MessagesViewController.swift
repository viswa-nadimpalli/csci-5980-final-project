//
//  MessagesViewController.swift
//  PatchPalsExtension
//
//  Created by Leo Curtis on 3/24/26.
//

import Messages
import SwiftUI

final class MessagesViewController: MSMessagesAppViewController {
    private let stickerSender = MessageStickerSender()
    private var hostingController: UIHostingController<MessagesStickerBrowserView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let rootView = MessagesStickerBrowserView(
            onSendSticker: { [weak self] sticker in
                guard let self else { return }
                await self.sendSticker(sticker)
            },
            onRequestExpandedPresentation: { [weak self] in
                self?.requestPresentationStyle(.expanded)
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        requestPresentationStyle(.expanded)
        NotificationCenter.default.post(name: .patchPalsMessagesExtensionDidBecomeActive, object: nil)
    }

    @MainActor
    private func sendSticker(_ sticker: Sticker) async {
        guard let conversation = activeConversation else { return }

        do {
            let msSticker = try await stickerSender.makeMSSticker(from: sticker)
            try await conversation.insert(msSticker)
        } catch {
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    @MainActor
    private func presentErrorAlert(message: String) {
        let alert = UIAlertController(title: "Couldn't Send Sticker", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

private extension MSConversation {
    func insert(_ sticker: MSSticker) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            insert(sticker) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
