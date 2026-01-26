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
    }

    // MARK: - Lifecycle

    func start() {
        guard !isActive else { return }

        meshManager.startAll()
        locationManager.startUpdating()
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

        print("[MeshCoordinator] Stopped")
    }

    func enterBackground() {
        // Reduce update frequency for background
        locationManager.updateMode = .background
        stopHeartbeat()
        stopLocationBroadcast()

        // Start background task for periodic updates
        scheduleBackgroundTask()

        print("[MeshCoordinator] Entered background mode")
    }

    func enterForeground() {
        locationManager.updateMode = .active
        startHeartbeat()
        startLocationBroadcast()

        print("[MeshCoordinator] Entered foreground mode")
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
        guard let userId = currentUserId else { return }

        let message = MeshMessagePayload.heartbeat(
            userId: userId,
            batteryLevel: gatewayManager.batteryLevel,
            hasService: gatewayManager.hasInternetAccess
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
        guard let userId = currentUserId else { return }

        let message = MeshMessagePayload.locationUpdate(userId: userId, location: location)
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
            print("[MeshCoordinator] Failed to sync location: \(error)")
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

    // MARK: - Background Tasks

    private func scheduleBackgroundTask() {
        #if os(iOS)
        let request = BGProcessingTaskRequest(identifier: "com.festivair.mesh-sync")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[MeshCoordinator] Failed to schedule background task: \(error)")
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
