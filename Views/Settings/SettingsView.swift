import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("FestivAir.DisplayName") private var displayName = "Festival Fan"
    @AppStorage("FestivAir.Emoji") private var emoji = "🎧"
    @AppStorage("FestivAir.NotifyBefore") private var notifyBefore = 10 // minutes
    @AppStorage("FestivAir.LowPowerMode") private var lowPowerMode = false

    @State private var showEditProfile = false
    @State private var showLeaveSquad = false
    @State private var showPaywall = false
    @State private var profileImage: UIImage?

    // Get or create current user
    @Query private var users: [User]

    private var currentUser: User? {
        let userId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId)
        return users.first { $0.id.uuidString == userId }
    }

    var body: some View {
        NavigationStack {
            List {
                // Profile section
                Section {
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack(spacing: 12) {
                            // Profile photo or emoji
                            ProfilePhotoView(
                                assetId: currentUser?.profilePhotoAssetId,
                                emoji: emoji,
                                size: 60,
                                isOnline: true
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    // Verification badge
                                    if let user = currentUser, user.isVerified {
                                        Image(systemName: user.verification.badgeIcon)
                                            .foregroundStyle(verificationColor(for: user.verification))
                                            .font(.caption)
                                    }
                                }

                                // Tier badge
                                if let user = currentUser, user.isPremium {
                                    HStack(spacing: 4) {
                                        Image(systemName: user.tier == .vip ? "crown.fill" : "star.fill")
                                            .font(.caption2)
                                        Text(user.tier.displayName)
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.purple)
                                } else {
                                    Text("Tap to edit profile")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Premium section
                Section {
                    if let user = currentUser, user.isPremium {
                        HStack {
                            Label(user.tier.displayName, systemImage: user.tier == .vip ? "crown.fill" : "star.fill")
                                .foregroundStyle(.purple)
                            Spacer()
                            if let expires = user.premiumExpiresAt {
                                Text("Until \(expires.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Label("Upgrade to Premium", systemImage: "star.fill")
                                Spacer()
                                Text("From $4.99/mo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Membership")
                } footer: {
                    if currentUser?.isPremium != true {
                        Text("Get larger squads, host parties, and more")
                    }
                }

                // Squad section
                Section("Squad") {
                    if let squad = appState.squadViewModel.currentSquad {
                        HStack {
                            Label(squad.name, systemImage: "person.3.fill")
                            Spacer()
                            Text("\(squad.memberCount) member\(squad.memberCount == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }

                        NavigationLink {
                            QRCodeView(
                                squadCode: squad.joinCode,
                                squadName: squad.name
                            )
                        } label: {
                            Label("Share Join Code", systemImage: "qrcode")
                        }

                        Button(role: .destructive) {
                            showLeaveSquad = true
                        } label: {
                            Label("Leave Squad", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        NavigationLink {
                            JoinSquadView()
                        } label: {
                            Label("Join or Create Squad", systemImage: "plus")
                        }
                    }
                }

                // Notifications section
                Section("Notifications") {
                    Picker("Notify before set", selection: $notifyBefore) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                    }

                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notification Settings", systemImage: "bell.badge")
                    }
                }

                // Battery section
                Section("Battery") {
                    Toggle(isOn: $lowPowerMode) {
                        Label("Low Power Mode", systemImage: "battery.25")
                    }
                    .onChange(of: lowPowerMode) { _, newValue in
                        appState.locationManager.updateMode = newValue ? .lowPower : .active
                    }

                    HStack {
                        Label("Current Battery", systemImage: "battery.100")
                        Spacer()
                        Text("\(appState.gatewayManager.batteryLevel)%")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Gateway Status", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text(appState.gatewayManager.isGateway ? "Active" : "Inactive")
                            .foregroundStyle(appState.gatewayManager.isGateway ? .purple : .secondary)
                    }
                }

                // Connection section
                Section {
                    HStack {
                        Label("Nearby Devices", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text("\(appState.meshManager.connectedPeers.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Internet", systemImage: "wifi")
                        Spacer()
                        Text(appState.gatewayManager.hasInternetAccess ? "Connected" : "Offline")
                            .foregroundStyle(appState.gatewayManager.hasInternetAccess ? .green : .orange)
                    }

                    HStack {
                        Label("Pending Sync", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text("\(appState.syncEngine.pendingChangesCount) changes")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Nearby devices help relay data for better coverage")
                }

                // Offline Data section
                Section {
                    NavigationLink {
                        OfflineMapsView()
                    } label: {
                        HStack {
                            Label("Offline Maps", systemImage: "map.fill")
                            Spacer()
                            Text(OfflineMapService.shared.formattedCacheSize)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Offline Data")
                } footer: {
                    Text("Download venue maps for offline use at festivals")
                }

                // About section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://festivair.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    Link(destination: URL(string: "https://festivair.app/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showEditProfile) {
                if let user = currentUser {
                    EditProfileView(user: user)
                } else {
                    // Fallback to simple edit view if no user exists
                    SimpleEditProfileView(displayName: $displayName, emoji: $emoji)
                }
            }
            .sheet(isPresented: $showPaywall) {
                // TODO: PaywallView()
                Text("Premium coming soon!")
                    .presentationDetents([.medium])
            }
            .alert("Leave Squad?", isPresented: $showLeaveSquad) {
                Button("Cancel", role: .cancel) {}
                Button("Leave", role: .destructive) {
                    Task {
                        try? await appState.squadViewModel.leaveSquad()
                    }
                }
            } message: {
                Text("You'll need to rejoin with a new code.")
            }
        }
    }

    // MARK: - Helpers

    private func verificationColor(for status: VerificationStatus) -> Color {
        switch status {
        case .vip: return .yellow
        case .creator: return .purple
        case .influencer: return .blue
        case .artist: return .pink
        case .none: return .gray
        }
    }
}

// MARK: - Simple Edit Profile View (fallback)
struct SimpleEditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var displayName: String
    @Binding var emoji: String
    @FocusState private var isNameFieldFocused: Bool

    // Generic person icons - not music emojis
    let iconOptions = ["👤", "👦", "👧", "👨", "👩", "🧑", "👱‍♂️", "👱‍♀️", "🧔", "👴", "👵", "🧓"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Text(emoji)
                            .font(.system(size: 80))
                        Spacer()
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(iconOptions, id: \.self) { option in
                            Text(option)
                                .font(.title)
                                .padding(8)
                                .background(emoji == option ? Color.purple.opacity(0.3) : Color.clear)
                                .clipShape(Circle())
                                .onTapGesture {
                                    emoji = option
                                }
                        }
                    }
                }

                Section {
                    TextField("Display Name", text: $displayName)
                        .focused($isNameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            dismiss()
                        }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Notification Settings View
struct NotificationSettingsView: View {
    @AppStorage("FestivAir.NotifyFavorites") private var notifyFavorites = true
    @AppStorage("FestivAir.NotifySquad") private var notifySquad = true
    @AppStorage("FestivAir.NotifyLowBattery") private var notifyLowBattery = true
    @AppStorage("FestivAir.NotifyOffline") private var notifyOffline = true

    var body: some View {
        Form {
            Section("Set Times") {
                Toggle("Favorite Artist Alerts", isOn: $notifyFavorites)
            }

            Section("Squad") {
                Toggle("Squad Messages", isOn: $notifySquad)
                Toggle("Member Low Battery", isOn: $notifyLowBattery)
                Toggle("Member Went Offline", isOn: $notifyOffline)
            }
        }
        .navigationTitle("Notifications")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
