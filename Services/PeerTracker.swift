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
        var status: UserStatus?

        var isStale: Bool {
            Date().timeIntervalSince(lastSeen) > Constants.PeerTracking.staleThreshold
        }

        var lastSeenText: String {
            if isOnline && !isStale {
                return "Online"
            }
            return lastSeen.timeAgo
        }

        /// Returns active status if not expired
        var activeStatus: UserStatus? {
            guard let status = status, status.isActive else { return nil }
            return status
        }
    }

    // MARK: - Published State
    @Published private(set) var peers: [String: PeerStatus] = [:]
    @Published private(set) var onlinePeers: [PeerStatus] = []
    @Published private(set) var offlinePeers: [PeerStatus] = []

    // MARK: - Configuration
    private let offlineThreshold: TimeInterval = Constants.PeerTracking.offlineThreshold
    private let removeThreshold: TimeInterval = Constants.PeerTracking.removeThreshold

    // MARK: - Private
    private var cleanupTimer: Timer?
    private var notificationManager: NotificationManager?

    // MARK: - Init
    init() {
        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
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
            location: location,
            status: nil
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

    func updatePeerStatus(id: String, userStatus: UserStatus) {
        guard var peerStatus = peers[id] else { return }

        // Handle out-of-order updates: only accept newer status
        if let existingStatus = peerStatus.status,
           userStatus.setAt < existingStatus.setAt {
            // Incoming status is older than current - ignore it
            print("[PeerTracker] Ignoring out-of-order status update (older than current)")
            return
        }

        peerStatus.status = userStatus
        peerStatus.lastSeen = Date()
        peers[id] = peerStatus
        updatePeerLists()
    }

    func markPeerOffline(id: String) {
        guard var status = peers[id] else { return }

        let wasOnline = status.isOnline
        status.isOnline = false
        // Clear status when peer goes offline to avoid showing stale status
        status.status = nil
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

    /// Register a remote squad member from CloudKit (initially offline until mesh discovers them)
    func registerRemoteMember(id: String, displayName: String, emoji: String) {
        // Don't overwrite if already exists (might have live mesh data)
        guard peers[id] == nil else { return }

        let status = PeerStatus(
            id: id,
            displayName: displayName,
            emoji: emoji,
            lastSeen: Date(),
            batteryLevel: nil,
            hasService: false,
            isOnline: false,  // Start as offline until mesh heartbeat arrives
            location: nil,
            status: nil
        )

        peers[id] = status
        updatePeerLists()
    }

    /// Clear all peers (used when leaving squad)
    func clearAllPeers() {
        peers.removeAll()
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
                // displayName is in peerId field, emoji is in squadId field (for heartbeats)
                let displayName = envelope.message.peerId ?? peerId
                let emoji = envelope.message.squadId ?? "🎧"

                // Extract location if included in heartbeat (for immediate map visibility)
                var location: Location? = nil
                if let locPayload = envelope.message.location {
                    location = Location(
                        latitude: locPayload.latitude,
                        longitude: locPayload.longitude,
                        accuracy: locPayload.accuracy,
                        timestamp: locPayload.timestamp,
                        source: LocationSource(rawValue: locPayload.source) ?? .mesh
                    )
                }

                updatePeer(
                    id: userId,
                    displayName: displayName,
                    emoji: emoji,
                    batteryLevel: envelope.message.batteryLevel,
                    hasService: envelope.message.hasService ?? false,
                    location: location
                )
            }

        case .locationUpdate:
            if let userId = envelope.message.userId,
               let locationPayload = envelope.message.location {
                // displayName is in peerId field, emoji is in squadId field
                let displayName = envelope.message.peerId ?? peerId
                let emoji = envelope.message.squadId ?? "🎧"

                // Create/update peer first (in case we get location before heartbeat)
                if peers[userId] == nil {
                    updatePeer(id: userId, displayName: displayName, emoji: emoji, batteryLevel: nil, hasService: false)
                } else if let name = envelope.message.peerId {
                    // Update display name if provided
                    if var status = peers[userId] {
                        status.displayName = name
                        if let e = envelope.message.squadId {
                            status.emoji = e
                        }
                        peers[userId] = status
                    }
                }

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

        case .statusUpdate:
            if let userId = envelope.message.userId,
               let statusPayload = envelope.message.status {
                let userStatus = statusPayload.toUserStatus()
                if peers[userId] != nil {
                    updatePeerStatus(id: userId, userStatus: userStatus)
                } else if let displayName = envelope.message.peerId {
                    // Create new peer with status
                    updatePeer(
                        id: userId,
                        displayName: displayName,
                        emoji: "🎧",
                        hasService: false
                    )
                    updatePeerStatus(id: userId, userStatus: userStatus)
                }
            }

        case .meetupPin:
            // Meetup pins are handled by MapViewModel
            // This is here for completeness - the message will be passed through
            break

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
