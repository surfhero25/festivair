import Foundation
import Combine
import BackgroundTasks

/// Coordinates mesh networking, location updates, and gateway sync
@MainActor
final class MeshCoordinator: ObservableObject {

    // MARK: - Published State
    @Published private(set) var isActive = false
    @Published private(set) var peerCount = 0
    @Published private(set) var lastHeartbeat: Date?
    @Published private(set) var meshStatus: MeshStatus = .disconnected

    enum MeshStatus {
        case disconnected
        case searching
        case connected
        case syncing
    }

    // MARK: - Dependencies
    private let meshManager: MeshNetworkManager
    private let locationManager: LocationManager
    private let gatewayManager: GatewayManager
    private let syncEngine: SyncEngine

    // MARK: - Timers
    private var heartbeatTimer: Timer?
    private var locationBroadcastTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - V2 Components
    private var locationTierManager: LocationTierManager?
    private var clusterManager: ClusterManager?
    private var messageSigner: MessageSigner?
    private var presencePulseTimer: Timer?
    private var ambientResponseTimer: Timer?
    private var navigateResponseTimer: Timer?
    private var bleBeacon: BLEBeaconService?

    @Published private(set) var currentTier: LocationTierManager.LocationTier = .idle
    @Published private(set) var clusterRole: ClusterManager.ClusterRole = .solo
    @Published private(set) var isSOSActive: Bool = false

    // MARK: - Haven Transport
    private var havenTransport: HavenTransportService?

    // MARK: - Configuration
    private let heartbeatInterval: TimeInterval = 30
    private let locationBroadcastInterval: TimeInterval = 30

    // MARK: - Current User
    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId)
    }

    // MARK: - Init
    init(
        meshManager: MeshNetworkManager,
        locationManager: LocationManager,
        gatewayManager: GatewayManager,
        syncEngine: SyncEngine
    ) {
        self.meshManager = meshManager
        self.locationManager = locationManager
        self.gatewayManager = gatewayManager
        self.syncEngine = syncEngine

        setupBindings()
        setupGatewayBroadcast()
    }

    /// Connect a Haven TCP transport as an additional message source
    func configureHaven(_ haven: HavenTransportService) {
        self.havenTransport = haven

        haven.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] envelope in
                self?.handleMeshMessage(envelope)
            }
            .store(in: &cancellables)

        #if DEBUG
        print("[MeshCoordinator] Haven transport configured")
        #endif
    }

    private func setupGatewayBroadcast() {
        // Broadcast gateway announcements via mesh when we become gateway
        gatewayManager.onGatewayAnnounce = { [weak self] message in
            self?.meshManager.broadcast(message)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isActive else { return }

        #if DEBUG
        print("[MeshCoordinator] Starting mesh coordinator...")
        print("[MeshCoordinator] userId: <redacted>")
        #endif

        meshManager.startAll()
        #if DEBUG
        print("[MeshCoordinator] Mesh manager started (advertising + browsing)")
        #endif

        locationManager.startUpdating()
        #if DEBUG
        print("[MeshCoordinator] Location manager started")
        #endif

        gatewayManager.startElection()

        startHeartbeat()
        startLocationBroadcast()

        isActive = true
        meshStatus = .searching

        Log.meshInfo("Coordinator started")
    }

    func stop() {
        meshManager.stopAll()
        locationManager.stopUpdating()
        gatewayManager.stopElection()

        stopHeartbeat()
        stopLocationBroadcast()

        isActive = false
        meshStatus = .disconnected

        #if DEBUG
        print("[MeshCoordinator] Stopped")
        #endif
    }

    func enterBackground() {
        // Reduce update frequency for background
        locationManager.updateMode = .background
        stopHeartbeat()
        stopLocationBroadcast()

        // BLE beacon continues in background — this is our lifeline
        bleBeacon?.startAdvertising()
        bleBeacon?.startScanning()

        // Start background task for periodic updates
        scheduleBackgroundTask()

        #if DEBUG
        print("[MeshCoordinator] Entered background mode")
        #endif
    }

    func enterForeground() {
        locationManager.updateMode = .active
        startHeartbeat()
        startLocationBroadcast()

        #if DEBUG
        print("[MeshCoordinator] Entered foreground mode")
        #endif
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendHeartbeat()
            }
        }
        // Send initial heartbeat
        sendHeartbeat()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func sendHeartbeat() {
        guard let userId = currentUserId, !userId.isEmpty else {
            #if DEBUG
            print("[MeshCoordinator] Cannot send heartbeat - no valid userId")
            #endif
            return
        }

        // Get current display name and emoji from UserDefaults (always fresh)
        let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) ?? "Festival Fan"
        let emoji = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.emoji) ?? "🎧"

        // Get current squad join code for peer filtering
        let joinCode = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode)

        // Include current location in heartbeat for immediate peer visibility
        let location = locationManager.currentLocation

        let message = MeshMessagePayload.heartbeat(
            userId: userId,
            displayName: displayName,
            emoji: emoji,
            batteryLevel: gatewayManager.batteryLevel,
            hasService: gatewayManager.hasInternetAccess,
            location: location,
            joinCode: joinCode
        )

        meshManager.broadcast(message)
        lastHeartbeat = Date()
    }

    // MARK: - Location Broadcasting

    private func startLocationBroadcast() {
        locationBroadcastTimer?.invalidate()

        // Listen for location updates
        locationManager.onLocationUpdate = { [weak self] location in
            self?.broadcastLocation(location)
        }
    }

    private func stopLocationBroadcast() {
        locationBroadcastTimer?.invalidate()
        locationBroadcastTimer = nil
        locationManager.onLocationUpdate = nil
    }

    private func broadcastLocation(_ location: Location) {
        guard let userId = currentUserId, !userId.isEmpty else {
            #if DEBUG
            print("[MeshCoordinator] Cannot broadcast location - no valid userId")
            #endif
            return
        }

        // Get current display name and emoji from UserDefaults (always fresh)
        let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) ?? "Festival Fan"
        let emoji = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.emoji) ?? "🎧"

        // Get current squad join code for peer filtering
        let joinCode = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode)

        let message = MeshMessagePayload.locationUpdate(userId: userId, displayName: displayName, emoji: emoji, location: location, joinCode: joinCode)
        meshManager.broadcast(message)

        // If we're the gateway, also sync to Firebase
        if gatewayManager.isGateway {
            Task {
                await syncLocationToCloud(location)
            }
        }
    }

    private func syncLocationToCloud(_ location: Location) async {
        guard let squadId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentSquadId),
              let userId = currentUserId else { return }

        do {
            try await CloudKitService.shared.updateLocation(
                squadId: squadId,
                userId: userId,
                latitude: location.latitude,
                longitude: location.longitude,
                accuracy: location.accuracy
            )
        } catch {
            #if DEBUG
            print("[MeshCoordinator] Failed to sync location: \(error)")
            #endif
        }
    }

    // MARK: - Bindings

    private func setupBindings() {
        // Track peer count
        meshManager.$connectedPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                self?.peerCount = peers.count
                self?.updateMeshStatus()
            }
            .store(in: &cancellables)

        // Gateway changes
        gatewayManager.$isGateway
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isGateway in
                if isGateway {
                    self?.meshStatus = .syncing
                    Task {
                        await self?.syncEngine.syncToCloud()
                    }
                }
            }
            .store(in: &cancellables)

        // Handle messages that need gateway sync
        meshManager.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] envelope, _ in
                self?.handleMeshMessage(envelope)
            }
            .store(in: &cancellables)
    }

    private func updateMeshStatus() {
        if peerCount > 0 {
            meshStatus = gatewayManager.isGateway ? .syncing : .connected
        } else if isActive {
            meshStatus = .searching
        } else {
            meshStatus = .disconnected
        }
    }

    private func handleMeshMessage(_ envelope: Any) {
        guard let meshEnvelope = envelope as? MeshEnvelope else { return }

        // Update gateway manager with peer signal strengths
        if meshEnvelope.message.type == .gatewayAnnounce,
           let peerId = meshEnvelope.message.peerId,
           let signalStrength = meshEnvelope.message.signalStrength,
           let batteryLevel = meshEnvelope.message.batteryLevel {
            gatewayManager.updatePeerSignalStrength(
                peerId: peerId,
                strength: signalStrength,
                battery: batteryLevel
            )
        }

        // Handle sync requests if we're the gateway
        if meshEnvelope.message.type == .syncRequest && gatewayManager.isGateway {
            Task {
                await syncEngine.pullFromCloud()
            }
        }
    }

    // MARK: - V2 Setup

    /// Initialize V2 demand-driven protocol components.
    /// Call after start() once userId is available.
    func setupV2() {
        guard let userId = currentUserId else { return }

        // Location tier manager
        let tierManager = LocationTierManager(userId: userId)
        tierManager.onTierChanged = { [weak self] tier in
            Task { @MainActor in
                self?.handleTierChange(tier)
            }
        }
        self.locationTierManager = tierManager

        // Cluster manager
        let cluster = ClusterManager(userId: userId)
        cluster.onRoleChanged = { [weak self] role in
            Task { @MainActor in
                self?.clusterRole = role
            }
        }
        self.clusterManager = cluster

        // Message signer
        do {
            self.messageSigner = try MessageSigner()
        } catch {
            #if DEBUG
            print("[MeshCoordinator] Failed to create MessageSigner: \(error)")
            #endif
        }

        // BLE beacon for background discovery
        let beacon = BLEBeaconService()
        beacon.onWakeNeeded = { [weak self] in
            Task { @MainActor in
                self?.handleBLEWake()
            }
        }
        beacon.onSOSDetected = { [weak self] _ in
            Task { @MainActor in
                // SOS detected via BLE — wake mesh immediately
                self?.handleBLEWake()
            }
        }
        beacon.onLocationRequested = { [weak self] in
            Task { @MainActor in
                // Someone nearby needs location — wake and respond
                self?.handleBLEWake()
            }
        }
        self.bleBeacon = beacon

        #if DEBUG
        print("[MeshCoordinator] BLE beacon initialized")
        #endif

        // Start V2 presence pulse (replaces heartbeat in V2)
        startPresencePulse()

        #if DEBUG
        print("[MeshCoordinator] V2 components initialized")
        #endif
    }

    // MARK: - V2 Tier Changes

    private func handleTierChange(_ tier: LocationTierManager.LocationTier) {
        currentTier = tier
        locationManager.applyTier(tier)

        // Stop all V2 response timers
        ambientResponseTimer?.invalidate()
        navigateResponseTimer?.invalidate()

        switch tier {
        case .idle:
            // GPS off, only presence pulse running
            break
        case .ambient:
            startAmbientResponses()
        case .navigate:
            startNavigateResponses()
        }
    }

    // MARK: - V2 Presence Pulse

    private func startPresencePulse() {
        presencePulseTimer?.invalidate()
        presencePulseTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.ProtocolV2.presencePulseInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sendPresencePulse()
            }
        }
        // Send initial pulse
        sendPresencePulse()
    }

    private func sendPresencePulse() {
        guard let userId = currentUserId,
              let signer = messageSigner,
              let joinCode = KeychainHelper.load(.currentJoinCode) ?? UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode)
        else { return }

        let pulse = V2PresencePulse(
            userId: userId,
            battery: gatewayManager.batteryLevel,
            isOnline: true,
            clusterID: clusterManager?.clusterID,
            clusterMembers: clusterManager?.clusterMembers
        )

        do {
            let envelope = try V2EnvelopeBuilder.build(
                type: .presencePulse,
                payload: pulse,
                originPeerId: userId,
                squadId: joinCode,
                signer: signer
            )
            let data = try envelope.encode()
            meshManager.broadcastRaw(data)
        } catch {
            #if DEBUG
            print("[MeshCoordinator] V2 presence pulse failed: \(error)")
            #endif
        }
    }

    // MARK: - V2 Location Responses

    private func startAmbientResponses() {
        let interval = Constants.BatteryTier.tier(for: Float(gatewayManager.batteryLevel) / 100.0) == .reduced
            ? Constants.ProtocolV2.ambientResponseReducedInterval
            : Constants.ProtocolV2.ambientResponseInterval

        ambientResponseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendAmbientResponses()
            }
        }
        sendAmbientResponses()
    }

    private func sendAmbientResponses() {
        guard let userId = currentUserId,
              let signer = messageSigner,
              let location = locationManager.currentLocation,
              let joinCode = KeychainHelper.load(.currentJoinCode) ?? UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode),
              let tierManager = locationTierManager
        else { return }

        let response = V2LocationResponse(
            latitude: location.latitude,
            longitude: location.longitude,
            clusterID: clusterManager?.clusterID,
            clusterMembers: clusterManager?.clusterMembers,
            heading: locationManager.currentHeading
        )

        // Send to each ambient requester directly
        for requesterID in tierManager.ambientRequesters {
            do {
                let envelope = try V2EnvelopeBuilder.build(
                    type: .locationResponse,
                    payload: response,
                    originPeerId: userId,
                    targetPeerId: requesterID,
                    squadId: joinCode,
                    signer: signer
                )
                let data = try envelope.encode()
                if let peer = meshManager.peerById(requesterID) {
                    meshManager.sendDirect(data, to: peer)
                }
            } catch {
                #if DEBUG
                print("[MeshCoordinator] V2 ambient response failed: \(error)")
                #endif
            }
        }
    }

    private func startNavigateResponses() {
        navigateResponseTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.ProtocolV2.preciseResponseInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sendNavigateResponses()
            }
        }
    }

    private func sendNavigateResponses() {
        guard let userId = currentUserId,
              let signer = messageSigner,
              let location = locationManager.currentLocation,
              let joinCode = KeychainHelper.load(.currentJoinCode) ?? UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode),
              let tierManager = locationTierManager
        else { return }

        let response = V2PreciseLocationResponse(
            latitude: location.latitude,
            longitude: location.longitude,
            heading: locationManager.currentHeading,
            speed: nil,
            accuracy: location.accuracy
        )

        for requesterID in tierManager.navigateRequesters {
            do {
                let envelope = try V2EnvelopeBuilder.build(
                    type: .preciseLocationResponse,
                    payload: response,
                    originPeerId: userId,
                    targetPeerId: requesterID,
                    squadId: joinCode,
                    signer: signer
                )
                let data = try envelope.encode()
                if let peer = meshManager.peerById(requesterID) {
                    meshManager.sendDirect(data, to: peer)
                }
            } catch {
                #if DEBUG
                print("[MeshCoordinator] V2 navigate response failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - V2 Incoming Message Handling

    func handleV2Message(_ data: Data) {
        guard let envelope = try? V2Envelope.decode(from: data) else { return }

        // Verify signature if we have the sender's public key
        // (For now, accept all valid envelopes — key exchange comes with squad join)

        do {
            try envelope.validatePayloadContent()
        } catch {
            #if DEBUG
            print("[MeshCoordinator] V2 message validation failed: \(error)")
            #endif
            return
        }

        switch envelope.type {
        case .locationRequest:
            if let payload = try? JSONDecoder().decode(V2LocationRequest.self, from: envelope.payload) {
                locationTierManager?.handleLocationRequest(from: payload.requesterID)
            }

        case .preciseLocationRequest:
            if let payload = try? JSONDecoder().decode(V2PreciseLocationRequest.self, from: envelope.payload) {
                locationTierManager?.handlePreciseLocationRequest(from: payload.requesterID, targetMemberID: payload.targetMemberID)
            }

        case .stopPreciseLocation:
            if let payload = try? JSONDecoder().decode(V2StopPreciseLocation.self, from: envelope.payload) {
                locationTierManager?.handleStopPreciseLocation(from: payload.requesterID)
            }

        case .requestRenewal:
            if let payload = try? JSONDecoder().decode(V2RequestRenewal.self, from: envelope.payload) {
                locationTierManager?.handleRequestRenewal(from: payload.requesterID, mode: payload.mode)
            }

        case .presencePulse:
            if let payload = try? JSONDecoder().decode(V2PresencePulse.self, from: envelope.payload) {
                clusterManager?.updatePeer(userId: payload.userId, batteryLevel: payload.battery, latitude: nil, longitude: nil)
            }

        case .locationResponse:
            if let payload = try? JSONDecoder().decode(V2LocationResponse.self, from: envelope.payload) {
                clusterManager?.updatePeer(userId: envelope.originPeerId, batteryLevel: 0, latitude: payload.latitude, longitude: payload.longitude)
            }

        case .preciseLocationResponse:
            if let payload = try? JSONDecoder().decode(V2PreciseLocationResponse.self, from: envelope.payload) {
                clusterManager?.updatePeer(userId: envelope.originPeerId, batteryLevel: 0, latitude: payload.latitude, longitude: payload.longitude)
            }

        case .sos:
            // SOS handled by SOS-specific handler (Phase 3)
            break

        default:
            break
        }
    }

    // MARK: - V2 SOS

    func activateSOS() {
        isSOSActive = true
        locationTierManager?.activateSOS()
        bleBeacon?.setSOSActive(true)
        // SOS broadcast loop handled by navigate response timer (already running at 3s)
    }

    func deactivateSOS() {
        isSOSActive = false
        locationTierManager?.deactivateSOS()
        bleBeacon?.setSOSActive(false)
    }

    // MARK: - BLE Background Wake

    /// Called when BLE beacon detects a peer needs communication
    private func handleBLEWake() {
        #if DEBUG
        print("[MeshCoordinator] BLE wake — restarting MPC")
        #endif

        // Restart MPC if not active
        if !meshManager.isAdvertising {
            meshManager.startAll()
        }

        // Send a presence pulse so peers know we're awake
        sendPresencePulse()
    }

    // MARK: - Background Tasks

    private func scheduleBackgroundTask() {
        #if os(iOS)
        let request = BGProcessingTaskRequest(identifier: "com.festivair.mesh-sync")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[MeshCoordinator] Failed to schedule background task: \(error)")
            #endif
        }
        #endif
    }

    func handleBackgroundTask() async {
        // Quick mesh sync in background
        sendHeartbeat()

        if let location = locationManager.currentLocation {
            broadcastLocation(location)
        }

        if gatewayManager.isGateway {
            await syncEngine.syncToCloud()
        }
    }
}

// MARK: - Background Task Registration
extension MeshCoordinator {
    static func registerBackgroundTasks() {
        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.festivair.mesh-sync",
            using: nil
        ) { task in
            // Handle task
            task.setTaskCompleted(success: true)
        }
        #endif
    }
}
