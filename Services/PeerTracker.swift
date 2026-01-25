import Foundation
import Combine

/// Tracks peer status, last seen times, and manages offline detection
@MainActor
final class PeerTracker: ObservableObject {

    // MARK: - Peer Status
    struct PeerStatus: Identifiable {
        let id: String
        var displayName: String
        var emoji: String
        var lastSeen: Date
        var batteryLevel: Int?
        var hasService: Bool
        var isOnline: Bool
        var location: Location?

        var isStale: Bool {
            Date().timeIntervalSince(lastSeen) > 120 // 2 minutes
        }

        var lastSeenText: String {
            if isOnline && !isStale {
                return "Online"
            }
            return lastSeen.timeAgo
        }
    }

    // MARK: - Published State
    @Published private(set) var peers: [String: PeerStatus] = [:]
    @Published private(set) var onlinePeers: [PeerStatus] = []
    @Published private(set) var offlinePeers: [PeerStatus] = []

    // MARK: - Configuration
    private let offlineThreshold: TimeInterval = 120 // 2 minutes
    private let removeThreshold: TimeInterval = 3600 // 1 hour

    // MARK: - Private
    private var cleanupTimer: Timer?
    private var notificationManager: NotificationManager?

    // MARK: - Init
    init() {
        startCleanupTimer()
    }

    func configure(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    // MARK: - Peer Management

    func updatePeer(
        id: String,
        displayName: String,
        emoji: String,
        batteryLevel: Int? = nil,
        hasService: Bool = true,
        location: Location? = nil
    ) {
        let wasOnline = peers[id]?.isOnline ?? false

        var status = peers[id] ?? PeerStatus(
            id: id,
            displayName: displayName,
            emoji: emoji,
            lastSeen: Date(),
            batteryLevel: batteryLevel,
            hasService: hasService,
            isOnline: true,
            location: location
        )

        status.displayName = displayName
        status.emoji = emoji
        status.lastSeen = Date()
        status.batteryLevel = batteryLevel
        status.hasService = hasService
        status.isOnline = true
        status.location = location

        peers[id] = status
        updatePeerLists()

        // Check for low battery notification
        if let battery = batteryLevel, battery <= 20 && wasOnline {
            Task {
                await notificationManager?.sendSquadMemberLowBattery(
                    memberName: displayName,
                    batteryLevel: battery
                )
            }
        }
    }

    func updatePeerLocation(id: String, location: Location) {
        guard var status = peers[id] else { return }
        status.location = location
        status.lastSeen = Date()
        peers[id] = status
        updatePeerLists()
    }

    func markPeerOffline(id: String) {
        guard var status = peers[id] else { return }

        let wasOnline = status.isOnline
        status.isOnline = false
        peers[id] = status
        updatePeerLists()

        // Send notification
        if wasOnline {
            Task {
                await notificationManager?.sendSquadMemberWentOffline(memberName: status.displayName)
            }
        }
    }

    func removePeer(id: String) {
        peers.removeValue(forKey: id)
        updatePeerLists()
    }

    // MARK: - Private Helpers

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStalePeers()
            }
        }
    }

    private func cleanupStalePeers() {
        let now = Date()

        for (id, status) in peers {
            let timeSinceLastSeen = now.timeIntervalSince(status.lastSeen)

            if timeSinceLastSeen > removeThreshold {
                // Remove very old peers
                peers.removeValue(forKey: id)
            } else if timeSinceLastSeen > offlineThreshold && status.isOnline {
                // Mark as offline
                markPeerOffline(id: id)
            }
        }

        updatePeerLists()
    }

    private func updatePeerLists() {
        let allPeers = Array(peers.values)
        onlinePeers = allPeers.filter { $0.isOnline && !$0.isStale }.sorted { $0.displayName < $1.displayName }
        offlinePeers = allPeers.filter { !$0.isOnline || $0.isStale }.sorted { $0.lastSeen > $1.lastSeen }
    }
}

// MARK: - Integration with MeshNetworkManager
extension PeerTracker {

    func handleMeshMessage(_ envelope: MeshEnvelope, from peerId: String) {
        switch envelope.message.type {
        case .heartbeat:
            if let userId = envelope.message.userId {
                updatePeer(
                    id: userId,
                    displayName: peerId, // Will be updated with real name
                    emoji: "🎧",
                    batteryLevel: envelope.message.batteryLevel,
                    hasService: envelope.message.hasService ?? false
                )
            }

        case .locationUpdate:
            if let userId = envelope.message.userId,
               let locationPayload = envelope.message.location {
                let location = Location(
                    latitude: locationPayload.latitude,
                    longitude: locationPayload.longitude,
                    accuracy: locationPayload.accuracy,
                    timestamp: locationPayload.timestamp,
                    source: LocationSource(rawValue: locationPayload.source) ?? .mesh
                )
                updatePeerLocation(id: userId, location: location)
            }

        case .findMe:
            if let userId = envelope.message.userId,
               let enabled = envelope.message.enabled,
               enabled {
                // Highlight this peer on the map
                if var status = peers[userId] {
                    status.lastSeen = Date()
                    peers[userId] = status
                    updatePeerLists()
                }
            }

        default:
            break
        }
    }

    func handlePeerDisconnected(_ peerId: String) {
        // Find peer by display name and mark offline
        for (id, status) in peers where status.displayName == peerId {
            markPeerOffline(id: id)
        }
    }
}

// MARK: - PeerStatus to User Conversion
extension PeerTracker.PeerStatus {

    /// Convert PeerStatus to a User object for display in ProfileView
    func toUser() -> User {
        let user = User(
            id: UUID(uuidString: id) ?? UUID(),
            displayName: displayName,
            avatarEmoji: emoji,
            lastSeen: lastSeen,
            batteryLevel: batteryLevel,
            hasService: hasService
        )

        // Copy location if available
        if let loc = location {
            user.updateLocation(loc)
        }

        return user
    }
}
