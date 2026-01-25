import SwiftUI

/// View for displaying another user's profile
struct ProfileView: View {
    let user: User
    @Environment(\.dismiss) private var dismiss
    @State private var showFullScreenPhoto = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    profileHeader

                    // Verification Badge
                    if user.isVerified {
                        verificationBadge
                    }

                    // Bio
                    if let bio = user.bio, !bio.isEmpty {
                        bioSection(bio)
                    }

                    // Social Links
                    if user.instagramHandle != nil || user.tiktokHandle != nil {
                        socialLinksSection
                    }

                    // Badges
                    if !user.userBadges.isEmpty {
                        badgesSection
                    }

                    // Stats
                    statsSection
                }
                .padding()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showFullScreenPhoto) {
                FullScreenPhotoView(assetId: user.profilePhotoAssetId, emoji: user.avatarEmoji)
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Profile Photo
            Button {
                if user.profilePhotoAssetId != nil {
                    showFullScreenPhoto = true
                }
            } label: {
                ProfilePhotoView(
                    assetId: user.profilePhotoAssetId,
                    emoji: user.avatarEmoji,
                    size: 120,
                    isOnline: true
                )
            }
            .buttonStyle(.plain)

            // Name + Verification
            HStack(spacing: 8) {
                Text(user.displayName)
                    .font(.title2)
                    .fontWeight(.bold)

                if user.isVerified {
                    Image(systemName: user.verification.badgeIcon)
                        .foregroundStyle(verificationColor)
                }
            }

            // Online Status
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Verification Badge

    private var verificationBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: user.verification.badgeIcon)
                .foregroundStyle(verificationColor)

            Text(user.verification.displayName)
                .font(.subheadline)
                .fontWeight(.medium)

            if let followers = formattedFollowers {
                Text("(\(followers) followers)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(verificationColor.opacity(0.1))
        .clipShape(Capsule())
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

    private var formattedFollowers: String? {
        let followers = user.totalFollowers
        guard followers > 0 else { return nil }

        if followers >= 1_000_000 {
            return String(format: "%.1fM", Double(followers) / 1_000_000)
        } else if followers >= 1_000 {
            return String(format: "%.1fK", Double(followers) / 1_000)
        }
        return "\(followers)"
    }

    // MARK: - Bio Section

    private func bioSection(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(bio)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Social Links Section

    private var socialLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Social")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                if let handle = user.instagramHandle {
                    socialButton(
                        icon: "camera.fill",
                        label: "@\(handle)",
                        color: .pink,
                        url: user.instagramURL
                    )
                }

                if let handle = user.tiktokHandle {
                    socialButton(
                        icon: "music.note",
                        label: "@\(handle)",
                        color: .black,
                        url: user.tiktokURL
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func socialButton(icon: String, label: String, color: Color, url: URL?) -> some View {
        Button {
            if let url = url {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(label)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Badges Section

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Badges")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(user.userBadges, id: \.self) { badge in
                    badgeView(badge)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badgeView(_ badge: UserBadge) -> some View {
        VStack(spacing: 4) {
            Image(systemName: badge.icon)
                .font(.title2)
                .foregroundStyle(.purple)

            Text(badge.displayName)
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                statItem(
                    icon: "battery.100",
                    value: user.batteryLevel != nil ? "\(user.batteryLevel!)%" : "--",
                    label: "Battery"
                )

                statItem(
                    icon: user.hasService ? "wifi" : "wifi.slash",
                    value: user.hasService ? "Online" : "Offline",
                    label: "Connection"
                )

                if user.isPremium {
                    statItem(
                        icon: user.tier == .vip ? "crown.fill" : "star.fill",
                        value: user.tier.displayName,
                        label: "Membership"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.purple)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Full Screen Photo View

struct FullScreenPhotoView: View {
    let assetId: String?
    let emoji: String
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(emoji)
                    .font(.system(size: 200))
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .task {
            if let assetId = assetId {
                image = await ImageCacheService.shared.image(forAssetId: assetId)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let user = User(displayName: "DJ Sparkle", avatarEmoji: "🎧")
    user.bio = "Festival lover | EDM enthusiast | Always chasing the bass drop"
    user.instagramHandle = "djsparkle"
    user.instagramFollowers = 25000
    user.verification = .influencer
    user.userBadges = [.earlyAdopter, .festivalVet]
    user.batteryLevel = 85
    user.hasService = true

    return ProfileView(user: user)
}
