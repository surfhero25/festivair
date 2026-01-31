import SwiftUI
import SwiftData
import Combine

@main
struct FestivAirApp: App {

    // MARK: - App Delegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - State Objects
    @StateObject private var appState = AppState()

    // MARK: - SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            Squad.self,
            SquadMembership.self,
            Event.self,
            Stage.self,
            SetTime.self,
            ChatMessage.self,
            Party.self,
            PartyAttendee.self
        ])
        // Use local storage only - CloudKit sync handled by CloudKitService manually
        // SwiftData's built-in CloudKit sync requires all fields optional + no unique constraints
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none  // Disabled - using custom CloudKitService instead
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appState.configure(modelContainer: sharedModelContainer)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - App State
@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State
    @Published var currentUser: User?
    @Published var currentSquad: Squad?
    @Published var isOnboarded: Bool

    // MARK: - Services
    let meshManager: MeshNetworkManager
    let locationManager: LocationManager
    let gatewayManager: GatewayManager
    let syncEngine: SyncEngine
    let notificationManager: NotificationManager
    let peerTracker: PeerTracker
    let cloudKit: CloudKitService

    // MARK: - Singleton Services
    let subscriptionManager = SubscriptionManager.shared
    let analyticsService = AnalyticsService.shared
    let sponsorService = SponsorService.shared

    // MARK: - ViewModels
    private(set) var squadViewModel: SquadViewModel!
    private(set) var chatViewModel: ChatViewModel!
    private(set) var mapViewModel: MapViewModel!
    private(set) var setTimesViewModel: SetTimesViewModel!
    private(set) var partiesViewModel: PartiesViewModel!

    // MARK: - Coordinator
    private(set) var meshCoordinator: MeshCoordinator!

    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    init() {
        // Check if onboarded
        isOnboarded = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.onboarded)

        // Get or create user ID
        let userId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId) ?? UUID().uuidString
        if UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId) == nil {
            UserDefaults.standard.set(userId, forKey: Constants.UserDefaultsKeys.userId)
        }

        let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) ?? "Festival Fan"

        // Initialize services
        meshManager = MeshNetworkManager(displayName: displayName)
        locationManager = LocationManager()
        gatewayManager = GatewayManager(peerId: userId)
        syncEngine = SyncEngine()
        notificationManager = NotificationManager()
        peerTracker = PeerTracker()
        cloudKit = CloudKitService.shared

        // Initialize ViewModels
        squadViewModel = SquadViewModel(cloudKit: cloudKit, meshManager: meshManager, peerTracker: peerTracker)
        chatViewModel = ChatViewModel(cloudKit: cloudKit, meshManager: meshManager, notificationManager: notificationManager)
        mapViewModel = MapViewModel(locationManager: locationManager, meshManager: meshManager, peerTracker: peerTracker)
        setTimesViewModel = SetTimesViewModel(notificationManager: notificationManager)
        partiesViewModel = PartiesViewModel()

        // Initialize Coordinator
        meshCoordinator = MeshCoordinator(
            meshManager: meshManager,
            locationManager: locationManager,
            gatewayManager: gatewayManager,
            syncEngine: syncEngine
        )

        // Configure peer tracker
        peerTracker.configure(notificationManager: notificationManager)

        // Register notification categories
        NotificationManager.registerCategories()
        // Note: Background tasks registered in AppDelegate.swift

        // Re-broadcast status when new peers connect
        setupStatusRebroadcast()
    }

    private func setupStatusRebroadcast() {
        meshManager.peerConnectedPublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main) // Debounce rapid connections
            .sink { [weak self] _ in
                self?.rebroadcastCurrentStatus()
            }
            .store(in: &cancellables)
    }

    private func rebroadcastCurrentStatus() {
        // Get current status from UserDefaults
        guard let status: UserStatus = UserDefaults.standard.codable(forKey: "FestivAir.CurrentUserStatus"),
              status.isActive else { return }

        guard let userId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId),
              let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) else { return }

        // Broadcast to the new peer
        let message = MeshMessagePayload.statusUpdate(userId: userId, displayName: displayName, status: status)
        meshManager.broadcast(message)
        print("[AppState] Re-broadcast status to new peers: \(status.displayText)")
    }

    // MARK: - Configuration

    func configure(modelContainer: ModelContainer) {
        let context = modelContainer.mainContext

        squadViewModel.configure(modelContext: context)
        setTimesViewModel.configure(modelContext: context)
        partiesViewModel.configure(modelContext: context)
        mapViewModel.configure(peerTracker: peerTracker)

        // Configure chat if we have a squad
        if let squad = squadViewModel.currentSquad {
            chatViewModel.configure(
                modelContext: context,
                squadId: squad.id,
                cloudSquadId: squad.firebaseId,
                joinCode: squad.joinCode
            )
        }

        // Import sample data if first launch OR if no events exist (app reinstalled)
        let hasData = !setTimesViewModel.events.isEmpty
        if !UserDefaults.standard.bool(forKey: "FestivAir.DataImported") || !hasData {
            Task {
                await setTimesViewModel.importFromBundle()
                UserDefaults.standard.set(true, forKey: "FestivAir.DataImported")
            }
        }

        // Start analytics tracking for premium users
        if subscriptionManager.currentTier != .free {
            analyticsService.startTracking()
        }

        // Store context for later use
        self.storedModelContext = context

        // Observe squad changes to reconfigure chat
        setupSquadObserver()
    }

    private var storedModelContext: ModelContext?

    private func setupSquadObserver() {
        squadViewModel.$currentSquad
            .dropFirst() // Skip initial value
            .sink { [weak self] squad in
                guard let self = self, let context = self.storedModelContext else { return }
                if let squad = squad {
                    self.chatViewModel.configure(
                        modelContext: context,
                        squadId: squad.id,
                        cloudSquadId: squad.firebaseId,
                        joinCode: squad.joinCode
                    )
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Onboarding

    func completeOnboarding(displayName: String, emoji: String) {
        // Use existing userId from init() — do NOT overwrite it, services already cached it
        UserDefaults.standard.set(displayName, forKey: Constants.UserDefaultsKeys.displayName)
        UserDefaults.standard.set(emoji, forKey: Constants.UserDefaultsKeys.emoji)
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.onboarded)

        isOnboarded = true
    }

    // MARK: - Service Lifecycle

    func startServices() {
        // Pre-configure mesh with userId even without a squad
        // This ensures heartbeats and location broadcasts have proper identity
        let userId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId) ?? ""
        if !userId.isEmpty {
            // Use a placeholder squadId - the mesh uses universalRelayEnabled=true
            // so it will connect to all FestivAir users regardless of squad
            meshManager.configure(squadId: "festivair-global", userId: userId)
            print("[AppState] Pre-configured mesh with userId: \(userId)")
        }

        meshCoordinator.start()
    }

    func stopServices() {
        meshCoordinator.stop()
    }

    func handleEnterBackground() {
        meshCoordinator.enterBackground()
    }

    func handleEnterForeground() {
        meshCoordinator.enterForeground()
        gatewayManager.refreshNetworkStatus()
    }
}
