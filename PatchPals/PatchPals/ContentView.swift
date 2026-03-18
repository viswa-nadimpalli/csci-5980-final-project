//
//  ContentView.swift
//  PatchPals
//
//  Created by Leo Curtis on 3/8/26.
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var userID = "4146544a-0464-42bd-b14e-6185b1e75f9a"
    @State private var loggedInUserID: String?
    @State private var packs: [Pack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loginError: String?

    var body: some View {
        Group {
            if let loggedInUserID {
                PacksDashboardView(
                    userID: loggedInUserID,
                    packs: $packs,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    onRefresh: {
                        await loadPacks(for: loggedInUserID)
                    },
                    onSignOut: signOut
                )
            } else {
                LoginView(
                    userID: $userID,
                    loginError: loginError,
                    onLogin: signIn
                )
            }
        }
        .task(id: loggedInUserID) {
            if loggedInUserID != nil {
                loginError = nil
                await loadPacks()
            }
        }
    }

    private func signIn() {
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard UUID(uuidString: trimmedUserID) != nil else {
            loginError = "Enter a valid user UUID to continue."
            return
        }

        loginError = nil
        loggedInUserID = trimmedUserID
    }

    private func signOut() {
        loggedInUserID = nil
        packs = []
        errorMessage = nil
        isLoading = false
    }

    private func loadPacks() async {
        guard let loggedInUserID else { return }
        await loadPacks(for: loggedInUserID)
    }

    private func loadPacks(for userID: String) async {
        isLoading = true
        errorMessage = nil

        do {
            packs = try await APIClient.shared.fetchPacks(requesterID: userID)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct LoginView: View {
    @Binding var userID: String
    let loginError: String?
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 14) {
                Text("PatchPals")
                    .font(.system(size: 40, weight: .bold, design: .rounded))

                Text("Sign in to manage your sticker packs and jump back into editing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("User ID")
                    .font(.headline)

                TextField("Enter your UUID", text: $userID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                if let loginError {
                    Text(loginError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(action: onLogin) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            )

            Spacer()
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.22), Color.blue.opacity(0.18), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

private struct PacksDashboardView: View {
    let userID: String
    @Binding var packs: [Pack]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () async -> Void
    let onSignOut: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 170), spacing: 18)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading packs...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn’t Load Packs",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if packs.isEmpty {
                    ContentUnavailableView(
                        "No Packs Yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Once packs are available for this account, they’ll show up here.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach($packs) { $pack in
                                NavigationLink {
                                    PackEditorView(
                                        userID: userID,
                                        pack: $pack
                                    )
                                } label: {
                                    PackCardView(pack: pack)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Your Packs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out", action: onSignOut)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await onRefresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Signed in as")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(userID)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(.bar)
            }
        }
    }
}

private struct PackCardView: View {
    let pack: Pack

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.orange, Color.pink.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 120)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding()
                }

            Text(pack.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(pack.description ?? "No description yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            Text("Tap to edit")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        )
    }
}

private struct PackEditorView: View {
    let userID: String
    @Binding var pack: Pack
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingStickers = false
    @State private var isUploadingSticker = false
    @State private var isDeletingStickerID: String?
    @State private var stickerActionError: String?

    var body: some View {
        Form {
            Section("Pack Details") {
                TextField("Pack name", text: $pack.name)
                TextField("Description", text: descriptionBinding, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Metadata") {
                LabeledContent("Pack ID", value: pack.id)
                LabeledContent("Owner ID", value: pack.ownerId)
            }

            Section("Stickers") {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(
                        isUploadingSticker ? "Uploading..." : "Upload Sticker",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(isUploadingSticker || isDeletingStickerID != nil)

                if let stickerActionError {
                    Text(stickerActionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if isLoadingStickers && stickers.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Loading stickers...")
                        Spacer()
                    }
                } else if stickers.isEmpty {
                    ContentUnavailableView(
                        "No Stickers Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Upload a sticker to start building this pack.")
                    )
                } else {
                    ForEach(stickers) { sticker in
                        StickerRowView(
                            sticker: sticker,
                            isDeleting: isDeletingStickerID == sticker.id,
                            onDelete: {
                                await deleteSticker(sticker)
                            }
                        )
                    }
                }
            }

    
        }
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: pack.id) {
            await loadStickers()
        }
        .task(id: selectedPhotoItem) {
            guard let selectedPhotoItem else { return }
            await uploadSticker(from: selectedPhotoItem)
        }
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { pack.description ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                pack.description = trimmed.isEmpty ? nil : newValue
            }
        )

    }

    private var stickers: [Sticker] {
        pack.stickers ?? []
    }

    private func loadStickers() async {
        guard !isLoadingStickers else { return }

        isLoadingStickers = true
        stickerActionError = nil
        defer { isLoadingStickers = false }

        do {
            pack.stickers = try await APIClient.shared.fetchStickers(
                packID: pack.id,
                userID: userID
            )
        } catch {
            stickerActionError = error.localizedDescription
        }
    }

    private func uploadSticker(from item: PhotosPickerItem) async {
        guard !isUploadingSticker else { return }

        isUploadingSticker = true
        stickerActionError = nil
        defer {
            isUploadingSticker = false
            selectedPhotoItem = nil
        }

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                throw UploadError.invalidImageData
            }

            let createdSticker = try await APIClient.shared.uploadSticker(
                packID: pack.id,
                userID: userID,
                imageData: imageData
            )

            if pack.stickers == nil {
                pack.stickers = []
            }
            pack.stickers?.insert(createdSticker, at: 0)
        } catch {
            stickerActionError = error.localizedDescription
        }
    }

    private func deleteSticker(_ sticker: Sticker) async {
        guard isDeletingStickerID == nil else { return }

        isDeletingStickerID = sticker.id
        stickerActionError = nil
        defer { isDeletingStickerID = nil }

        do {
            try await APIClient.shared.deleteSticker(
                stickerID: sticker.id,
                userID: userID
            )
            pack.stickers?.removeAll { $0.id == sticker.id }
        } catch {
            stickerActionError = error.localizedDescription
        }
    }
}

private struct StickerRowView: View {
    let sticker: Sticker
    let isDeleting: Bool
    let onDelete: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: sticker.downloadURL.flatMap(URL.init(string:))) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(sticker.id)
                    .font(.footnote.monospaced())
                    .lineLimit(1)

                Text(sticker.uploadedBy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(role: .destructive) {
                Task {
                    await onDelete()
                }
            } label: {
                if isDeleting {
                    ProgressView()
                } else {
                    Image(systemName: "trash")
                }
            }
            .disabled(isDeleting)
        }
    }
}

private enum UploadError: LocalizedError {
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "The selected image couldn't be loaded."
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
