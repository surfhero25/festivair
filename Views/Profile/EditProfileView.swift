import SwiftUI
import PhotosUI

/// View for editing the current user's profile
struct EditProfileView: View {
    @Bindable var user: User
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Photo picker
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var profileImage: UIImage?

    // Form fields
    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var instagramHandle: String = ""
    @State private var tiktokHandle: String = ""

    // UI State
    @State private var showingEmojiPicker = false
    @State private var selectedEmoji: String = ""
    @State private var isLoading = false
    @State private var showingSaveError = false
    @State private var errorMessage = ""
    @State private var showingPreview = false

    var body: some View {
        NavigationStack {
            Form {
                // Profile Photo Section
                profilePhotoSection

                // Basic Info Section
                basicInfoSection

                // Bio Section
                bioSection

                // Social Links Section
                socialLinksSection

                // Verification Status
                verificationSection

                // Premium Status
                if user.isPremium {
                    premiumSection
                }

                // Preview Button
                Section {
                    Button {
                        showingPreview = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Preview Profile", systemImage: "eye")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                    .disabled(isLoading || displayName.isEmpty)
                }
            }
            .onAppear {
                loadCurrentValues()
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    await loadSelectedPhoto(newItem)
                }
            }
            .alert("Error Saving", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingEmojiPicker) {
                EmojiPickerSheet(selectedEmoji: $selectedEmoji)
            }
            .sheet(isPresented: $showingPreview) {
                previewSheet
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    // MARK: - Profile Photo Section

    private var profilePhotoSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    // Current photo or emoji
                    ZStack {
                        if let image = profileImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            Text(selectedEmoji)
                                .font(.system(size: 50))
                                .frame(width: 100, height: 100)
                                .background(Color.purple.opacity(0.2))
                                .clipShape(Circle())
                        }

                        // Edit badge
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "camera.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            }
                            .offset(x: 35, y: 35)
                    }

                    // Photo picker
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Text("Change Photo")
                            .font(.subheadline)
                            .foregroundStyle(.purple)
                    }

                    // Emoji picker button
                    Button {
                        showingEmojiPicker = true
                    } label: {
                        Text("Change Emoji")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        Section("Basic Info") {
            TextField("Display Name", text: $displayName)
                .textContentType(.name)

            HStack {
                Text("Emoji Avatar")
                Spacer()
                Text(selectedEmoji)
                    .font(.title2)
            }
        }
    }

    // MARK: - Bio Section

    private var bioSection: some View {
        Section {
            TextField("Tell others about yourself...", text: $bio, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("Bio")
        } footer: {
            Text("\(bio.count)/\(Constants.Profile.maxBioLength) characters")
                .foregroundStyle(bio.count > Constants.Profile.maxBioLength ? .red : .secondary)
        }
    }

    // MARK: - Social Links Section

    private var socialLinksSection: some View {
        Section {
            HStack {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.pink)
                    .frame(width: 24)
                TextField("Instagram username", text: $instagramHandle)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }

            HStack {
                Image(systemName: "music.note")
                    .foregroundStyle(.primary)
                    .frame(width: 24)
                TextField("TikTok username", text: $tiktokHandle)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Social Links")
        } footer: {
            Text("Link your socials to get auto-verified based on follower count")
        }
    }

    // MARK: - Verification Section

    private var verificationSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verification Status")
                    if user.isVerified {
                        HStack(spacing: 4) {
                            Image(systemName: user.verification.badgeIcon)
                                .foregroundStyle(verificationColor)
                            Text(user.verification.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not verified")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if user.isVerified {
                    Image(systemName: user.verification.badgeIcon)
                        .font(.title2)
                        .foregroundStyle(verificationColor)
                }
            }

            // Follower thresholds info
            VStack(alignment: .leading, spacing: 8) {
                thresholdRow(
                    icon: "checkmark.seal.fill",
                    label: "Influencer",
                    threshold: "10K+ followers",
                    color: .blue,
                    achieved: user.totalFollowers >= Constants.Verification.influencerFollowers
                )
                thresholdRow(
                    icon: "star.fill",
                    label: "Creator",
                    threshold: "50K+ followers",
                    color: .purple,
                    achieved: user.totalFollowers >= Constants.Verification.creatorFollowers
                )
                thresholdRow(
                    icon: "crown.fill",
                    label: "VIP",
                    threshold: "100K+ followers",
                    color: .yellow,
                    achieved: user.totalFollowers >= Constants.Verification.vipFollowers
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("Verification")
        } footer: {
            Text("Connect your social accounts to automatically earn verification badges")
        }
    }

    private func thresholdRow(icon: String, label: String, threshold: String, color: Color, achieved: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(achieved ? color : .gray.opacity(0.5))
                .frame(width: 20)
            Text(label)
                .font(.caption)
            Spacer()
            Text(threshold)
                .font(.caption)
                .foregroundStyle(.secondary)
            if achieved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var verificationColor: Color {
        switch user.verification {
        case .vip: return .yellow
        case .creator: return .purple
        case .influencer: return .blue
        case .artist: return .pink
        case .none: return .gray
        }
    }

    // MARK: - Premium Section

    private var premiumSection: some View {
        Section("Membership") {
            HStack {
                Image(systemName: user.tier == .vip ? "crown.fill" : "star.fill")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text("\(user.tier.displayName) Member")
                        .fontWeight(.medium)
                    if let expires = user.premiumExpiresAt {
                        Text("Expires \(expires.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Preview Sheet

    private var previewSheet: some View {
        NavigationStack {
            // Create a preview user with current edits
            let previewUser = createPreviewUser()
            ProfileView(user: previewUser)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showingPreview = false
                        }
                    }
                }
        }
    }

    private func createPreviewUser() -> User {
        let preview = User(displayName: displayName, avatarEmoji: selectedEmoji)
        preview.bio = bio.isEmpty ? nil : bio
        preview.instagramHandle = instagramHandle.isEmpty ? nil : instagramHandle
        preview.instagramFollowers = user.instagramFollowers
        preview.tiktokHandle = tiktokHandle.isEmpty ? nil : tiktokHandle
        preview.tiktokFollowers = user.tiktokFollowers
        preview.verification = user.verification
        preview.userBadges = user.userBadges
        preview.tier = user.tier
        preview.premiumExpiresAt = user.premiumExpiresAt
        preview.batteryLevel = user.batteryLevel
        preview.hasService = user.hasService
        preview.profilePhotoAssetId = user.profilePhotoAssetId
        return preview
    }

    // MARK: - Actions

    private func loadCurrentValues() {
        displayName = user.displayName
        selectedEmoji = user.avatarEmoji
        bio = user.bio ?? ""
        instagramHandle = user.instagramHandle ?? ""
        tiktokHandle = user.tiktokHandle ?? ""

        // Load existing profile photo
        if let assetId = user.profilePhotoAssetId {
            Task {
                profileImage = await ImageCacheService.shared.image(forAssetId: assetId)
            }
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImageData = data
                if let uiImage = UIImage(data: data) {
                    // Resize if needed
                    let maxDimension = CGFloat(Constants.Profile.profilePhotoMaxDimension)
                    profileImage = uiImage.resized(toMaxDimension: maxDimension)
                }
            }
        } catch {
            print("[EditProfile] Failed to load photo: \(error)")
        }
    }

    private func saveProfile() {
        // Validate
        guard !displayName.isEmpty else { return }
        guard bio.count <= Constants.Profile.maxBioLength else {
            errorMessage = "Bio is too long. Maximum \(Constants.Profile.maxBioLength) characters."
            showingSaveError = true
            return
        }

        isLoading = true

        Task {
            do {
                // Update user fields
                user.displayName = displayName
                user.avatarEmoji = selectedEmoji
                user.bio = bio.isEmpty ? nil : bio
                user.instagramHandle = instagramHandle.isEmpty ? nil : instagramHandle
                user.tiktokHandle = tiktokHandle.isEmpty ? nil : tiktokHandle

                // Upload photo if changed
                if selectedImageData != nil,
                   let image = profileImage {
                    // Compress for upload
                    if let compressedData = image.jpegData(compressionQuality: 0.8) {
                        if compressedData.count <= Constants.Profile.profilePhotoMaxSizeBytes {
                            // TODO: Upload to CloudKit and get asset ID
                            // let assetId = try await CloudKitService.shared.uploadProfilePhoto(compressedData, userId: user.id.uuidString)
                            // user.profilePhotoAssetId = assetId

                            // For now, cache locally with a temporary key
                            let tempKey = "profile_\(user.id.uuidString)"
                            await ImageCacheService.shared.cache(image, forKey: tempKey)
                        } else {
                            throw ProfileError.photoTooLarge
                        }
                    }
                }

                // Update verification from social followers if connected
                user.updateVerificationFromFollowers()

                // Save context
                try modelContext.save()

                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showingSaveError = true
                }
            }
        }
    }
}

// MARK: - Profile Errors

enum ProfileError: LocalizedError {
    case photoTooLarge
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .photoTooLarge:
            return "Photo is too large. Please choose a smaller image."
        case .uploadFailed:
            return "Failed to upload photo. Please try again."
        }
    }
}

// MARK: - Emoji Picker Sheet

struct EmojiPickerSheet: View {
    @Binding var selectedEmoji: String
    @Environment(\.dismiss) private var dismiss

    private let festivalEmojis = [
        "🎧", "🎤", "🎸", "🎹", "🥁", "🎺", "🎷", "🪗",
        "🎵", "🎶", "🎼", "🎪", "🎭", "🎨", "🎬", "🎯",
        "🔥", "⚡️", "✨", "💫", "🌟", "⭐️", "🌈", "🦋",
        "🦄", "🐉", "👽", "🤖", "👾", "🎃", "💀", "👻",
        "😎", "🤩", "🥳", "😈", "👑", "💎", "🔮", "🪩",
        "🍕", "🍔", "🌮", "🍦", "🍩", "🍪", "🧁", "🎂",
        "🍺", "🍻", "🥂", "🍾", "🍹", "🧉", "☕️", "🫖"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                    ForEach(festivalEmojis, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.title)
                                .frame(width: 44, height: 44)
                                .background(selectedEmoji == emoji ? Color.purple.opacity(0.3) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview {
    let user = User(displayName: "DJ Sparkle", avatarEmoji: "🎧")
    user.bio = "Festival lover"
    user.instagramHandle = "djsparkle"
    user.instagramFollowers = 25000

    return EditProfileView(user: user)
}
