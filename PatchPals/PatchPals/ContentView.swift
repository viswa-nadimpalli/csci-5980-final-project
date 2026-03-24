//
//  ContentView.swift
//  PatchPals
//
//  Created by Leo Curtis on 3/8/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Root

struct ContentView: View {
    @State private var loggedInUserID: String?
    @State private var packs: [Pack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let loggedInUserID {
                PacksDashboardView(
                    userID: loggedInUserID,
                    packs: $packs,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    onRefresh: { await loadPacks(for: loggedInUserID) },
                    onSignOut: signOut
                )
            } else {
                LoginView(onLoggedIn: { userID in
                    loggedInUserID = userID
                })
            }
        }
        .task(id: loggedInUserID) {
            if let id = loggedInUserID {
                await loadPacks(for: id)
            }
        }
    }

    private func signOut() {
        loggedInUserID = nil
        packs = []
        errorMessage = nil
        isLoading = false
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

// MARK: - Login

private enum LoginTab { case signIn, createAccount }

private struct LoginView: View {
    let onLoggedIn: (String) -> Void

    @State private var tab: LoginTab = .signIn

    // Sign in
    @State private var userID = ""
    @State private var signInError: String?

    // Create account
    @State private var email = ""
    @State private var password = ""
    @State private var isCreating = false
    @State private var createError: String?

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

            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $tab) {
                    Text("Sign In").tag(LoginTab.signIn)
                    Text("Create Account").tag(LoginTab.createAccount)
                }
                .pickerStyle(.segmented)

                if tab == .signIn {
                    signInForm
                } else {
                    createAccountForm
                }
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
        .animation(.easeInOut(duration: 0.2), value: tab)
    }

    @ViewBuilder private var signInForm: some View {
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

            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(action: attemptSignIn) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder private var createAccountForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Email")
                .font(.headline)

            TextField("you@example.com", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            Text("Password")
                .font(.headline)

            SecureField("Password", text: $password)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            if let createError {
                Text(createError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(action: attemptCreateAccount) {
                if isCreating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text("Create Account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(isCreating)
        }
    }

    private func attemptSignIn() {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else {
            signInError = "Enter a valid user UUID to continue."
            return
        }
        signInError = nil
        onLoggedIn(trimmed)
    }

    private func attemptCreateAccount() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            createError = "Email is required."
            return
        }
        guard !password.isEmpty else {
            createError = "Password is required."
            return
        }

        isCreating = true
        createError = nil

        Task {
            do {
                let user = try await APIClient.shared.createUser(email: trimmedEmail, password: password)
                onLoggedIn(user.id)
            } catch {
                createError = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - Dashboard

private struct PacksDashboardView: View {
    let userID: String
    @Binding var packs: [Pack]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () async -> Void
    let onSignOut: () -> Void

    @State private var showCreateSheet = false
    @State private var isDeletingPackID: String?

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 18)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading packs...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn't Load Packs",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if packs.isEmpty {
                    ContentUnavailableView(
                        "No Packs Yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap + to create your first sticker pack.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach($packs) { $pack in
                                NavigationLink {
                                    PackEditorView(userID: userID, pack: $pack, onPackDeleted: {
                                        packs.removeAll { $0.id == pack.id }
                                    })
                                } label: {
                                    PackCardView(pack: pack, isOwner: pack.ownerId == userID)
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
                    HStack(spacing: 14) {
                        Button {
                            Task { await onRefresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        Button {
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
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
            .sheet(isPresented: $showCreateSheet) {
                CreatePackSheet(userID: userID) { newPack in
                    packs.append(newPack)
                }
            }
        }
    }
}

// MARK: - Pack Card

private struct PackCardView: View {
    let pack: Pack
    let isOwner: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.pink.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 120)

                Image(systemName: "face.smiling")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding()
            }

            HStack(alignment: .top) {
                Text(pack.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                if isOwner {
                    Text("Owner")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.orange)
                        )
                }
            }

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
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        )
    }
}

// MARK: - Create Pack Sheet

private struct CreatePackSheet: View {
    let userID: String
    let onCreated: (Pack) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pack name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...5)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("New Pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .overlay {
                if isCreating {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("Creating...")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        error = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let pack = try await APIClient.shared.createPack(
                name: trimmedName,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                ownerID: userID
            )
            onCreated(pack)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - Pack Editor

private struct PackEditorView: View {
    let userID: String
    @Binding var pack: Pack
    let onPackDeleted: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingStickers = false
    @State private var isUploadingSticker = false
    @State private var isDeletingStickerID: String?
    @State private var stickerActionError: String?
    @State private var showDeletePackAlert = false
    @State private var isDeletingPack = false
    @State private var showMembers = false

    @Environment(\.dismiss) private var dismiss

    private var isOwner: Bool { pack.ownerId == userID }
    private var stickers: [Sticker] { pack.stickers ?? [] }

    private let stickerColumns = [
        GridItem(.adaptive(minimum: 100), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Pack Details card
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pack Details")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                    Divider().padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        HStack {
                            Text("Name").foregroundStyle(.secondary)
                            Spacer()
                            Text(pack.name)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.horizontal, 16)

                        HStack(alignment: .top) {
                            Text("Description").foregroundStyle(.secondary)
                            Spacer()
                            Text(pack.description ?? "No description.")
                                .foregroundStyle(pack.description == nil ? .secondary : .primary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 20)

                // Metadata card
                VStack(alignment: .leading, spacing: 0) {
                    Text("Metadata")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                    Divider().padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        metadataRow(label: "Pack ID", value: pack.id)
                        Divider().padding(.horizontal, 16)
                        metadataRow(label: "Owner ID", value: pack.ownerId)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 20)

                // Stickers section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Stickers")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            if isUploadingSticker {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Uploading...")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundStyle(.orange)
                            } else {
                                Label("Add", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .disabled(isUploadingSticker || isDeletingStickerID != nil)
                    }
                    .padding(.horizontal, 20)

                    if let stickerActionError {
                        Text(stickerActionError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                    }

                    if isLoadingStickers && stickers.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading stickers...")
                            Spacer()
                        }
                        .padding(.vertical, 32)
                    } else if stickers.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("No stickers yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Tap Add to upload your first sticker.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: stickerColumns, spacing: 10) {
                            ForEach(stickers) { sticker in
                                StickerThumbnailView(
                                    sticker: sticker,
                                    isDeleting: isDeletingStickerID == sticker.id,
                                    onDelete: { await deleteSticker(sticker) }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showMembers = true
                        } label: {
                            Label("Manage Members", systemImage: "person.2")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeletePackAlert = true
                        } label: {
                            Label("Delete Pack", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: pack.id) {
            await loadStickers()
        }
        .task(id: selectedPhotoItem) {
            guard let selectedPhotoItem else { return }
            await uploadSticker(from: selectedPhotoItem)
        }
        .alert("Delete Pack", isPresented: $showDeletePackAlert) {
            Button("Delete", role: .destructive) {
                Task { await deletePack() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(pack.name)\" and all its stickers will be permanently deleted. This cannot be undone.")
        }
        .navigationDestination(isPresented: $showMembers) {
            MembersView(userID: userID, pack: pack)
        }
        .overlay {
            if isDeletingPack {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("Deleting pack...")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func loadStickers() async {
        guard !isLoadingStickers else { return }
        isLoadingStickers = true
        stickerActionError = nil
        defer { isLoadingStickers = false }
        do {
            pack.stickers = try await APIClient.shared.fetchStickers(packID: pack.id, userID: userID)
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
                throw APIError(detail: "The selected image couldn't be loaded.")
            }

            // Detect content type from the item's UTType
            let contentType: String
            if let type_ = item.supportedContentTypes.first {
                if type_.conforms(to: .jpeg) {
                    contentType = "image/jpeg"
                } else if type_.conforms(to: .webP) {
                    contentType = "image/webp"
                } else if type_.conforms(to: .gif) {
                    contentType = "image/gif"
                } else {
                    contentType = "image/png"
                }
            } else {
                contentType = "image/png"
            }

            let createdSticker = try await APIClient.shared.uploadSticker(
                packID: pack.id,
                userID: userID,
                imageData: imageData,
                contentType: contentType
            )

            if pack.stickers == nil { pack.stickers = [] }
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
            try await APIClient.shared.deleteSticker(stickerID: sticker.id, userID: userID)
            pack.stickers?.removeAll { $0.id == sticker.id }
        } catch {
            stickerActionError = error.localizedDescription
        }
    }

    private func deletePack() async {
        isDeletingPack = true
        do {
            try await APIClient.shared.deletePack(packID: pack.id, requesterID: userID)
            onPackDeleted()
            dismiss()
        } catch {
            stickerActionError = error.localizedDescription
            isDeletingPack = false
        }
    }
}

// MARK: - Sticker Thumbnail

private struct StickerThumbnailView: View {
    let sticker: Sticker
    let isDeleting: Bool
    let onDelete: () async -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: sticker.downloadURL.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                default:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay { ProgressView() }
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Task { await onDelete() }
            } label: {
                if isDeleting {
                    ProgressView()
                        .scaleEffect(0.75)
                        .frame(width: 26, height: 26)
                        .background(.regularMaterial, in: Circle())
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.black.opacity(0.6), in: Circle())
                }
            }
            .offset(x: 6, y: -6)
            .disabled(isDeleting)
        }
    }
}

// MARK: - Members View

private struct MembersView: View {
    let userID: String
    let pack: Pack

    @State private var addUserID = ""
    @State private var addRole: PackRole = .viewer
    @State private var isAdding = false
    @State private var addResult: String?
    @State private var addIsError = false

    @State private var removeUserID = ""
    @State private var isRemoving = false
    @State private var removeResult: String?
    @State private var removeIsError = false

    var body: some View {
        Form {
            Section {
                TextField("User ID (UUID)", text: $addUserID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Role", selection: $addRole) {
                    ForEach(PackRole.allCases, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }

                Button {
                    Task { await addMember() }
                } label: {
                    if isAdding {
                        HStack {
                            ProgressView().scaleEffect(0.85)
                            Text("Adding...")
                        }
                    } else {
                        Text("Add Member")
                    }
                }
                .disabled(addUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)

                if let addResult {
                    Text(addResult)
                        .font(.footnote)
                        .foregroundStyle(addIsError ? .red : .green)
                }
            } header: {
                Text("Add Member")
            } footer: {
                Text("Contributor: can upload & add members. Viewer: read-only access.")
            }

            Section {
                TextField("User ID (UUID)", text: $removeUserID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button(role: .destructive) {
                    Task { await removeMember() }
                } label: {
                    if isRemoving {
                        HStack {
                            ProgressView().scaleEffect(0.85)
                            Text("Removing...")
                        }
                    } else {
                        Text("Remove Member")
                    }
                }
                .disabled(removeUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRemoving)

                if let removeResult {
                    Text(removeResult)
                        .font(.footnote)
                        .foregroundStyle(removeIsError ? .red : .green)
                }
            } header: {
                Text("Remove Member")
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addMember() async {
        let trimmed = addUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else {
            addResult = "Enter a valid UUID."
            addIsError = true
            return
        }

        isAdding = true
        addResult = nil
        defer { isAdding = false }

        do {
            _ = try await APIClient.shared.addMember(
                packID: pack.id,
                requesterID: userID,
                userID: trimmed,
                role: addRole
            )
            addResult = "Added successfully as \(addRole.displayName.lowercased())."
            addIsError = false
            addUserID = ""
        } catch {
            addResult = error.localizedDescription
            addIsError = true
        }
    }

    private func removeMember() async {
        let trimmed = removeUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else {
            removeResult = "Enter a valid UUID."
            removeIsError = true
            return
        }

        isRemoving = true
        removeResult = nil
        defer { isRemoving = false }

        do {
            try await APIClient.shared.removeMember(
                packID: pack.id,
                requesterID: userID,
                userID: trimmed
            )
            removeResult = "Removed successfully."
            removeIsError = false
            removeUserID = ""
        } catch {
            removeResult = error.localizedDescription
            removeIsError = true
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
