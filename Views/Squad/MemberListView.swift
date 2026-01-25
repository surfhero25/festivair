import SwiftUI

struct MemberListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var selectedPeer: PeerTracker.PeerStatus?
    @State private var showingProfile = false

    private var peerTracker: PeerTracker {
        appState.peerTracker
    }

    private var squadViewModel: SquadViewModel {
        appState.squadViewModel
    }

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId)
    }

    var body: some View {
        NavigationStack {
            Group {
                if peerTracker.onlinePeers.isEmpty && peerTracker.offlinePeers.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No squad members yet")
                            .font(.headline)
                        Text("Share your join code to invite friends")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if let squad = squadViewModel.currentSquad {
                            Button {
                                UIPasteboard.general.string = squad.joinCode
                            } label: {
                                HStack {
                                    Text(squad.joinCode)
                                        .font(.title2.monospaced().bold())
                                    Image(systemName: "doc.on.doc")
                                }
                                .foregroundStyle(.purple)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        // Current user section
                        if currentUserId != nil {
                            Section {
                                CurrentUserRow(
                                    isGateway: appState.gatewayManager.isGateway,
                                    batteryLevel: appState.gatewayManager.batteryLevel
                                )
                            } header: {
                                Text("You")
                            }
                        }

                        // Online members
                        if !peerTracker.onlinePeers.isEmpty {
                            Section {
                                ForEach(peerTracker.onlinePeers) { peer in
                                    Button {
                                        selectedPeer = peer
                                        showingProfile = true
                                    } label: {
                                        MemberRow(peer: peer, isGateway: false)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                HStack {
                                    Text("Online")
                                    Spacer()
                                    Text("\(peerTracker.onlinePeers.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Offline members
                        if !peerTracker.offlinePeers.isEmpty {
                            Section {
                                ForEach(peerTracker.offlinePeers) { peer in
                                    Button {
                                        selectedPeer = peer
                                        showingProfile = true
                                    } label: {
                                        MemberRow(peer: peer, isGateway: false)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                HStack {
                                    Text("Offline")
                                    Spacer()
                                    Text("\(peerTracker.offlinePeers.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Squad Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                if let peer = selectedPeer {
                    ProfileView(user: peer.toUser())
                }
            }
        }
    }
}

// MARK: - Current User Row
struct CurrentUserRow: View {
    let isGateway: Bool
    let batteryLevel: Int

    private var displayName: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) ?? "You"
    }

    private var emoji: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.emoji) ?? "🎧"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Text(emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.purple.opacity(0.2))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(.purple, lineWidth: 2)
                )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(displayName)
                        .fontWeight(.medium)

                    if isGateway {
                        Text("Gateway")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.2))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }

                Text("This is you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Battery
            HStack(spacing: 4) {
                Image(systemName: batteryIcon(for: batteryLevel))
                    .foregroundStyle(batteryColor(for: batteryLevel))
                Text("\(batteryLevel)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func batteryIcon(for level: Int) -> String {
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }

    private func batteryColor(for level: Int) -> Color {
        if level > 50 { return .green }
        if level > 25 { return .orange }
        return .red
    }
}

// MARK: - Member Row
struct MemberRow: View {
    let peer: PeerTracker.PeerStatus
    let isGateway: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Text(peer.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(peer.isOnline ? Color.purple.opacity(0.2) : Color.gray.opacity(0.2))
                .clipShape(Circle())

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(peer.displayName)
                        .fontWeight(.medium)

                    if isGateway {
                        Text("Gateway")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.2))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }

                    if peer.hasService && peer.isOnline {
                        Image(systemName: "wifi")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Text(peer.lastSeenText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Battery
            if let battery = peer.batteryLevel {
                HStack(spacing: 4) {
                    Image(systemName: batteryIcon(for: battery))
                        .foregroundStyle(batteryColor(for: battery))
                    Text("\(battery)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func batteryIcon(for level: Int) -> String {
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }

    private func batteryColor(for level: Int) -> Color {
        if level > 50 { return .green }
        if level > 25 { return .orange }
        return .red
    }
}

#Preview {
    MemberListView()
        .environmentObject(AppState())
}
