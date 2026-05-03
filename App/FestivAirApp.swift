import SwiftUI
import SwiftData
import Combine
import AuthenticationServices

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

    // MARK: - Shared Instance (for background task access)
    static weak var shared: AppState?

    // MARK: - Published State
    @Published var currentUser: User?
    @Published var currentSquad: Squad?
    @Published var isOnboarded: Bool

    /// True only when user has a valid Apple ID stored in Keychain.
    /// All squad/SOS features require authentication — no anonymous users.
    var isAuthenticated: Bool {
        KeychainHelper.load(.appleUserIdentifier) != nil
    }

    // MARK: - Services
    let meshManager: MeshNetworkManager
    let locationManager: LocationManager
    let gatewayManager: GatewayManager
    let syncEngine: SyncEngine
    let notificationManager: NotificationManager
    let peerTracker: PeerTracker
    let cloudKit: CloudKitService
    let havenTransport: HavenTransportService
    let sosManager: SOSManager

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
        // Migrate from UserDefaults to Keychain if needed
        KeychainHelper.migrateFromUserDefaultsIfNeeded()
        KeychainHelper.mirrorIdentityToUserDefaults()

        // Check if onboarded
        isOnboarded = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.onboarded)

        // Load identity from Keychain (authoritative source)
        // Only Apple-authenticated users have a userId — no random UUID fallback
        let userId: String
        if let stored = KeychainHelper.load(.userId) {
            userId = stored
        } else {
            // No userId — user must complete onboarding with Sign in with Apple
            userId = ""
        }

        // Note: Can't use isOnboarded here since stored properties not yet initialized
        #if DEBUG
        print("[AppState] Init - userId: <redacted>")
        #endif

        let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) ?? "Festival Fan"
        let _ = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.emoji) ?? "🎧"
        let onboardedStatus = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.onboarded)

        // Log startup state for debugging (use local vars, not self)
        #if DEBUG
        print("[App] 🚀 Starting - isOnboarded: \(onboardedStatus), displayName: \(displayName)")
        #endif

        // Initialize services
        meshManager = MeshNetworkManager(displayName: displayName)
        locationManager = LocationManager()
        gatewayManager = GatewayManager(peerId: userId)
        syncEngine = SyncEngine()
        notificationManager = NotificationManager()
        peerTracker = PeerTracker()
        cloudKit = CloudKitService.shared
        havenTransport = HavenTransportService()
        sosManager = SOSManager(meshManager: meshManager, locationManager: locationManager)

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

        // Configure Haven TCP transport
        meshCoordinator.configureHaven(havenTransport)
        meshCoordinator.configureSOSManager(sosManager)

        // Configure peer tracker
        peerTracker.configure(notificationManager: notificationManager)

        // Register notification categories
        NotificationManager.registerCategories()
        // Note: Background tasks registered in AppDelegate.swift

        // Re-broadcast status when new peers connect
        setupStatusRebroadcast()

        // Forward NotificationManager changes to trigger SwiftUI updates
        // This ensures the chat badge updates when unreadChatCount changes
        notificationManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Validate Apple ID credential if user signed in with Apple
        validateAppleCredentialIfNeeded()

        // Set shared instance for background task access
        AppState.shared = self
    }

    /// Check if Apple ID credential is still valid (not revoked).
    /// If no Apple credential exists, forces re-onboarding regardless of the onboarded flag.
    private func validateAppleCredentialIfNeeded() {
        guard let appleUserId = KeychainHelper.load(.appleUserIdentifier) else {
            // No Apple credential — this install is unauthenticated.
            // Force back through onboarding so the user must sign in with Apple.
            if isOnboarded {
                #if DEBUG
                print("[AppleAuth] No Apple credential but isOnboarded=true (old install) — requiring re-auth")
                #endif
                isOnboarded = false
            }
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: appleUserId) { [weak self] state, error in
            Task { @MainActor in
                switch state {
                case .authorized:
                    #if DEBUG
                    print("[AppleAuth] Credential still valid")
                    #endif
                case .revoked:
                    #if DEBUG
                    print("[AppleAuth] Credential was revoked - clearing user data and requiring re-auth")
                    #endif
                    self?.handleAppleCredentialRevoked()
                case .notFound:
                    #if DEBUG
                    print("[AppleAuth] Credential not found - may need to re-authenticate")
                    #endif
                    // Don't clear immediately - could be a temporary issue
                case .transferred:
                    #if DEBUG
                    print("[AppleAuth] Credential transferred")
                    #endif
                @unknown default:
                    break
                }
            }
        }
    }

    /// Handle when Apple ID credential is revoked.
    /// Forces the user back through onboarding to re-authenticate.
    private func handleAppleCredentialRevoked() {
        // Clear Apple-specific keychain data
        KeychainHelper.clearUserData()

        // Force back to onboarding — Apple auth is mandatory
        isOnboarded = false
        UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.onboarded)

        #if DEBUG
        print("[AppleAuth] Credential revoked — cleared auth data, sending back to onboarding")
        #endif
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

        guard let userId = KeychainHelper.currentUserId,
              let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) else { return }

        // Get current squad join code for filtering
        let joinCode = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode)

        // Broadcast to the new peer
        let message = MeshMessagePayload.statusUpdate(userId: userId, displayName: displayName, status: status, joinCode: joinCode)
        meshManager.broadcast(message)
        #if DEBUG
        print("[AppState] Re-broadcast status to new peers: \(status.displayText)")
        #endif
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
                cloudSquadId: squad.cloudKitRecordId,
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
                        cloudSquadId: squad.cloudKitRecordId,
                        joinCode: squad.joinCode
                    )
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Onboarding

    func completeOnboarding(displayName: String, emoji: String) {
        // Require Apple auth — userId must be the Apple user identifier from Keychain.
        // No anonymous UUID fallback. If this is nil the user hasn't authenticated yet.
        guard let userId = KeychainHelper.load(.userId), !userId.isEmpty else {
            #if DEBUG
            print("[App] ❌ Cannot complete onboarding — no Apple-authenticated userId in Keychain")
            #endif
            return
        }

        // Double-check Apple identifier is also present (belt-and-suspenders)
        guard KeychainHelper.load(.appleUserIdentifier) != nil else {
            #if DEBUG
            print("[App] ❌ Cannot complete onboarding — missing Apple user identifier")
            #endif
            return
        }

        // CRITICAL: Save to Keychain FIRST (persists across app reinstalls)
        // Do this before setting isOnboarded to avoid race condition on crash
        KeychainHelper.saveCurrentUserId(userId)
        KeychainHelper.save(displayName, for: .displayName)
        KeychainHelper.save(emoji, for: .emoji)

        // Save to UserDefaults (for app components)
        UserDefaults.standard.set(userId, forKey: Constants.UserDefaultsKeys.userId)
        UserDefaults.standard.set(displayName, forKey: Constants.UserDefaultsKeys.displayName)
        UserDefaults.standard.set(emoji, forKey: Constants.UserDefaultsKeys.emoji)
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.onboarded)

        // Force immediate write to disk (important if app is killed quickly)
        UserDefaults.standard.synchronize()

        DebugLogger.success("Onboarding complete - name: \(displayName)", category: "App")
        #if DEBUG
        print("[App] ✅ Onboarding complete - name: \(displayName)")
        print("[App] 🔐 User data saved to Keychain (will persist across reinstalls)")
        #endif

        isOnboarded = true
    }

    // MARK: - Service Lifecycle

    func startServices() {
        // Pre-configure mesh with userId even without a squad
        // This ensures heartbeats and location broadcasts have proper identity
        let userId = KeychainHelper.currentUserId ?? ""
        if !userId.isEmpty {
            // Use a placeholder squadId - the mesh uses universalRelayEnabled=true
            // so it will connect to all FestivAir users regardless of squad
            meshManager.configure(squadId: "festivair-global", userId: userId)
            #if DEBUG
            print("[AppState] Pre-configured mesh")
            #endif
        }

        meshCoordinator.start()
        havenTransport.start()
    }

    func stopServices() {
        havenTransport.stop()
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
