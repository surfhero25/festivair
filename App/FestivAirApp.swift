import SwiftUI
import SwiftData

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
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.festivair.app") // Enable CloudKit sync
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
        squadViewModel = SquadViewModel(cloudKit: cloudKit, meshManager: meshManager)
        chatViewModel = ChatViewModel(cloudKit: cloudKit, meshManager: meshManager)
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
        MeshCoordinator.registerBackgroundTasks()
    }

    // MARK: - Configuration

    func configure(modelContainer: ModelContainer) {
        let context = modelContainer.mainContext

        squadViewModel.configure(modelContext: context)
        setTimesViewModel.configure(modelContext: context)
        partiesViewModel.configure(modelContext: context)

        // Configure chat if we have a squad
        if let squad = squadViewModel.currentSquad {
            chatViewModel.configure(
                modelContext: context,
                squadId: squad.id,
                cloudSquadId: squad.firebaseId
            )
        }

        // Import sample data if first launch
        if !UserDefaults.standard.bool(forKey: "FestivAir.DataImported") {
            Task {
                await setTimesViewModel.importFromBundle()
                UserDefaults.standard.set(true, forKey: "FestivAir.DataImported")
            }
        }

        // Start analytics tracking for premium users
        if subscriptionManager.currentTier != .free {
            analyticsService.startTracking()
        }
    }

    // MARK: - Onboarding

    func completeOnboarding(displayName: String, emoji: String) {
        let userId = UUID().uuidString
        UserDefaults.standard.set(userId, forKey: Constants.UserDefaultsKeys.userId)
        UserDefaults.standard.set(displayName, forKey: Constants.UserDefaultsKeys.displayName)
        UserDefaults.standard.set(emoji, forKey: Constants.UserDefaultsKeys.emoji)
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.onboarded)

        isOnboarded = true
    }

    // MARK: - Service Lifecycle

    func startServices() {
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
    }
}
