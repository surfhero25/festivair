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
            // Use abs() to handle clock skew between devices
            abs(Date().timeIntervalSince(lastSeen)) > Constants.PeerTracking.staleThreshold
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

        // MARK: - V2 Stale Pin Properties

        /// V2: Last known location for stale pin display
        var lastKnownLatitude: Double?
        var lastKnownLongitude: Double?
        var lastLocationUpdate: Date?

        /// V2: Cluster info
        var clusterID: String?
        var isClusterReporter: Bool = false

        /// V2: How stale is this peer's location?
        var locationStaleness: LocationStaleness {
            guard let lastUpdate = lastLocationUpdate else { return .unknown }
            let age = Date().timeIntervalSince(lastUpdate)
            if age < Constants.ProtocolV2.stalePinFadeAge { return .fresh }
            if age < Constants.ProtocolV2.stalePinMaxAge { return .stale }
            return .expired
        }

        enum LocationStaleness {
            case fresh      // < 5 min — full opacity
            case stale      // 5 min - 1 hour — faded with timestamp
            case expired    // > 1 hour — hidden
            case unknown    // never had location
        }

        /// V2: Opacity for map pin based on staleness
        var pinOpacity: Double {
            switch locationStaleness {
            case .fresh: return 1.0
            case .stale: return 0.4
            case .expired, .unknown: return 0.0
            }
        }

        /// V2: Time ago text for stale pins
        var locationAgeText: String? {
            guard let lastUpdate = lastLocationUpdate else { return nil }
            let age = Date().timeIntervalSince(lastUpdate)
            if age < 60 { return "Just now" }
            if age < 3600 { return "\(Int(age / 60)) min ago" }
            return nil  // expired — don't show
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
        // Capture state BEFORE any mutations for battery check
        let previousBattery = peers[id]?.batteryLevel
        let wasOnline = peers[id]?.isOnline ?? false
        let capturedDisplayName = displayName  // Capture for async use

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

        // Check for low battery notification - only notify if:
        // 1. They were online and still are
        // 2. Battery is low (≤20%)
        // 3. Battery dropped from above 20% to below (avoid repeat notifications)
        if let battery = batteryLevel,
           battery <= 20,
           wasOnline,
           (previousBattery == nil || previousBattery! > 20) {
            Task { [weak self] in
                await self?.notificationManager?.sendSquadMemberLowBattery(
                    memberName: capturedDisplayName,
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
            #if DEBUG
        print("[PeerTracker] Ignoring out-of-order status update (older than current)")
        #endif
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

    /// Clear all peers (used when leaving/creating/joining squad)
    func clearAllPeers() {
        let count = peers.count
        peers.removeAll()
        updatePeerLists()
        #if DEBUG
        print("[PeerTracker] Cleared \(count) peers")
        #endif
    }

    // MARK: - V2 Location Updates

    /// Updates a peer's location from a V2 locationResponse or preciseLocationResponse
    func updatePeerLocationV2(userId: String, latitude: Double, longitude: Double, clusterID: String?, isReporter: Bool = false) {
        guard var peer = peers[userId] else { return }
        peer.lastKnownLatitude = latitude
        peer.lastKnownLongitude = longitude
        peer.lastLocationUpdate = Date()
        peer.clusterID = clusterID
        peer.isClusterReporter = isReporter
        peer.lastSeen = Date()
        peer.isOnline = true
        peers[userId] = peer
    }

    /// Returns all peers grouped by clusterID for map display
    var peersByCluster: [String?: [PeerStatus]] {
        Dictionary(grouping: Array(peers.values)) { $0.clusterID }
    }

    /// Returns peers that should be visible on the map (not expired)
    var visiblePeers: [PeerStatus] {
        peers.values.filter { $0.locationStaleness != .expired && $0.locationStaleness != .unknown }
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

    /// Get my current squad's join code for filtering
    private var myJoinCode: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode)
    }

    func handleMeshMessage(_ envelope: MeshEnvelope, from peerId: String) {
        switch envelope.message.type {
        case .heartbeat:
            if let userId = envelope.message.userId {
                // IMPORTANT: Only track peers from the same squad
                // If they have a joinCode that doesn't match ours, ignore them
                let peerJoinCode = envelope.message.joinCode
                let peerName = envelope.message.peerId ?? "Unknown"

                if let myCode = myJoinCode, let theirCode = peerJoinCode {
                    if myCode != theirCode {
                        // Different squad - ignore this peer
                        #if DEBUG
                        print("[PeerTracker] ❌ Ignoring \(peerName) - different squad")
                        #endif
                        return
                    }
                    #if DEBUG
                    print("[PeerTracker] ✅ Accepting \(peerName) - same squad")
                    #endif
                } else if myJoinCode != nil && peerJoinCode == nil {
                    // We're in a squad, they're not - ignore (they might be on old version)
                    // However, also allow registered remote members through
                    if peers[userId] == nil {
                        #if DEBUG
                        print("[PeerTracker] ❌ Ignoring \(peerName) - no joinCode and not registered")
                        #endif
                        return
                    }
                    #if DEBUG
                    print("[PeerTracker] ⚠️ Accepting \(peerName) - no joinCode but already registered")
                    #endif
                } else if myJoinCode == nil {
                    // No squad - don't accept any peers as squad members
                    #if DEBUG
                    print("[PeerTracker] ❌ Ignoring \(peerName) - not in a squad yet")
                    #endif
                    return
                }

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
                // IMPORTANT: Only track peers from the same squad
                let peerJoinCode = envelope.message.joinCode
                if let myCode = myJoinCode, let theirCode = peerJoinCode {
                    if myCode != theirCode {
                        return  // Different squad
                    }
                } else if myJoinCode != nil && peerJoinCode == nil {
                    // We're in a squad, they're not - only allow if already registered
                    if peers[userId] == nil {
                        return
                    }
                } else if myJoinCode == nil {
                    // Not in a squad - don't accept location updates
                    return
                }

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
                // Only process status updates from same squad
                let peerJoinCode = envelope.message.joinCode

                // No squad - don't accept status updates
                guard myJoinCode != nil else { return }

                // Different squad - ignore
                if let myCode = myJoinCode, let theirCode = peerJoinCode, myCode != theirCode {
                    return
                }

                let userStatus = statusPayload.toUserStatus()
                if peers[userId] != nil {
                    updatePeerStatus(id: userId, userStatus: userStatus)
                } else if let displayName = envelope.message.peerId {
                    // Only create new peer if they're in our squad
                    if peerJoinCode != nil && peerJoinCode == myJoinCode {
                        updatePeer(
                            id: userId,
                            displayName: displayName,
                            emoji: "🎧",
                            hasService: false
                        )
                        updatePeerStatus(id: userId, userStatus: userStatus)
                    }
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
