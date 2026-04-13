import Foundation
import SwiftData
import Combine

@MainActor
final class SquadViewModel: ObservableObject {

    // MARK: - Published State
    @Published var currentSquad: Squad?
    @Published var members: [User] = []
    @Published var memberLocations: [UUID: Location] = [:]
    @Published var isLoading = false
    @Published var error: SquadError?

    // MARK: - Dependencies
    private let cloudKit: CloudKitService
    private let meshManager: MeshNetworkManager
    private let peerTracker: PeerTracker
    private let subscriptionManager = SubscriptionManager.shared
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Current User
    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId)
    }

    /// Gets the current user ID, or creates one if it doesn't exist
    /// This is a failsafe in case AppState.init() didn't save it properly
    private func getOrCreateUserId() -> String {
        if let existing = currentUserId {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: Constants.UserDefaultsKeys.userId)
        #if DEBUG
        print("[SquadVM] Created missing userId")
        #endif
        return newId
    }

    // MARK: - Init
    init(cloudKit: CloudKitService = .shared, meshManager: MeshNetworkManager, peerTracker: PeerTracker) {
        self.cloudKit = cloudKit
        self.meshManager = meshManager
        self.peerTracker = peerTracker
        setupMeshListener()
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadCurrentSquad()
    }

    // MARK: - Squad Operations

    func createSquad(name: String, joinCode: String? = nil) async throws {
        // Always ensure we have a userId (creates one if missing)
        let userId = getOrCreateUserId()

        isLoading = true
        defer { isLoading = false }

        // Use provided code or generate new one
        let finalJoinCode = joinCode ?? Squad.generateJoinCode()

        // Create local squad
        let squad = Squad(name: name, joinCode: finalJoinCode)

        // Create membership
        if let user = try await getOrCreateCurrentUser() {
            let membership = SquadMembership(user: user, squad: squad, isAdmin: true)
            modelContext?.insert(squad)
            modelContext?.insert(membership)
            try modelContext?.save()
        }

        // Sync to CloudKit (optional, works offline - ignore errors for local-first)
        if cloudKit.isAvailable {
            do {
                let cloudId = try await cloudKit.createSquad(name: name, joinCode: finalJoinCode, creatorId: userId)
                squad.firebaseId = cloudId // Reusing field for CloudKit ID
                try modelContext?.save()
            } catch {
                // CloudKit sync failed (e.g., schema not deployed) - continue with local-only squad
                #if DEBUG
                print("[Squad] CloudKit sync failed, continuing with local squad: \(error.localizedDescription)")
                #endif
            }
        }

        currentSquad = squad
        UserDefaults.standard.set(squad.id.uuidString, forKey: Constants.UserDefaultsKeys.currentSquadId)
        UserDefaults.standard.set(finalJoinCode, forKey: Constants.UserDefaultsKeys.currentJoinCode)

        // CRITICAL: Clear all peers when creating squad - they were added before filtering was active
        peerTracker.clearAllPeers()
        #if DEBUG
        print("[SquadVM] Cleared peers on squad creation")
        #endif

        await loadMembers()

        // Configure mesh networking
        meshManager.configure(squadId: squad.id.uuidString, userId: userId)
    }

    func joinSquad(code: String) async throws {
        // Validate join code format before any network calls
        let validChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard normalizedCode.count == Constants.Squad.codeLength,
              normalizedCode.allSatisfy({ validChars.contains($0) }) else {
            throw SquadError.squadNotFound  // Invalid format treated as not found
        }

        // Always ensure we have a userId (creates one if missing)
        let userId = getOrCreateUserId()

        isLoading = true
        defer { isLoading = false }

        // Try CloudKit first (optional - works offline/local-only)
        var squadName = "Squad"
        var cloudSquadId: String?
        var existingMemberIds: [String] = []

        #if DEBUG
        print("[SquadVM] Joining squad, CloudKit available: \(cloudKit.isAvailable)")
        #endif

        if cloudKit.isAvailable {
            do {
                if let found = try await cloudKit.findSquad(byCode: normalizedCode) {
                    #if DEBUG
                    print("[SquadVM] ✅ Found squad in CloudKit: '\(found.name)' with \(found.memberIds.count) members")
                    #endif
                    squadName = found.name
                    cloudSquadId = found.id
                    existingMemberIds = found.memberIds
                    let memberCount = found.memberIds.count

                    // Squad limit enforcement:
                    // - Anyone can JOIN a squad if it's below the absolute max (25)
                    // - The squad creator's tier determines how many members they can INVITE
                    // - This means 1 Basic user can create a squad and 14 free friends can join
                    if memberCount >= Constants.Squad.maxMembers {
                        throw SquadError.tierLimitReached(currentLimit: Constants.Squad.maxMembers, tier: .vip)
                    }

                    try await cloudKit.joinSquad(squadId: found.id, userId: userId)
                    #if DEBUG
                    print("[SquadVM] ✅ Joined squad successfully")
                    #endif
                } else {
                    #if DEBUG
                    print("[SquadVM] ⚠️ Squad NOT found in CloudKit - creating local only")
                    #endif
                }
            } catch let error as SquadError {
                // Re-throw squad-specific errors (like tier limit)
                throw error
            } catch {
                // CloudKit sync failed - continue with local squad
                #if DEBUG
                print("[SquadVM] ❌ CloudKit error: \(error.localizedDescription)")
                #endif
            }
        } else {
            #if DEBUG
            print("[SquadVM] ⚠️ CloudKit not available")
            #endif
        }

        // Check for existing local squad with this join code (avoid duplicates)
        let existingSquad: Squad?
        if let modelContext = modelContext {
            let joinCode = normalizedCode
            let descriptor = FetchDescriptor<Squad>(
                predicate: #Predicate { $0.joinCode == joinCode }
            )
            existingSquad = try? modelContext.fetch(descriptor).first
        } else {
            existingSquad = nil
        }

        let squad: Squad
        if let existing = existingSquad {
            // Reuse existing local squad
            squad = existing
            if let cloudId = cloudSquadId {
                squad.firebaseId = cloudId
            }
        } else {
            // Create new local squad
            squad = Squad(name: squadName, joinCode: normalizedCode)
            squad.firebaseId = cloudSquadId
            modelContext?.insert(squad)
        }

        if let user = try await getOrCreateCurrentUser() {
            // Check if membership already exists
            let existingMember = squad.memberships?.contains(where: { $0.user?.id == user.id }) ?? false
            if !existingMember {
                let membership = SquadMembership(user: user, squad: squad)
                modelContext?.insert(membership)
            }
            try modelContext?.save()
        }

        currentSquad = squad
        UserDefaults.standard.set(squad.id.uuidString, forKey: Constants.UserDefaultsKeys.currentSquadId)
        UserDefaults.standard.set(normalizedCode, forKey: Constants.UserDefaultsKeys.currentJoinCode)

        // CRITICAL: Clear all peers when joining squad - they were added before filtering was active
        peerTracker.clearAllPeers()
        #if DEBUG
        print("[SquadVM] Cleared peers on squad join")
        #endif

        await loadMembers()

        // Fetch and register other squad members from CloudKit
        await registerSquadMembers(memberIds: existingMemberIds, excludingUserId: userId)

        // Configure mesh networking
        meshManager.configure(squadId: squad.id.uuidString, userId: userId)
    }

    /// Fetch member profiles from CloudKit, create local records, and register with PeerTracker
    private func registerSquadMembers(memberIds: [String], excludingUserId: String) async {
        guard cloudKit.isAvailable else { return }
        guard let squad = currentSquad, let modelContext = modelContext else { return }

        let otherMemberIds = memberIds.filter { $0 != excludingUserId }
        guard !otherMemberIds.isEmpty else { return }

        do {
            let profiles = try await cloudKit.getSquadMemberProfiles(memberIds: otherMemberIds)
            #if DEBUG
            print("[SquadVM] Fetched \(profiles.count) member profiles from CloudKit")
            #endif

            for profile in profiles {
                // Register with PeerTracker for mesh networking
                peerTracker.registerRemoteMember(
                    id: profile.id,
                    displayName: profile.displayName,
                    emoji: profile.emoji
                )

                // Create local User record if doesn't exist
                let profileId = profile.id
                let userDescriptor = FetchDescriptor<User>(
                    predicate: #Predicate { $0.firebaseId == profileId }
                )

                let existingUser: User
                if let found = try? modelContext.fetch(userDescriptor).first {
                    existingUser = found
                    // Update display name/emoji in case they changed
                    existingUser.displayName = profile.displayName
                    existingUser.avatarEmoji = profile.emoji
                } else {
                    // Create new local user
                    let newUser = User(displayName: profile.displayName, avatarEmoji: profile.emoji)
                    newUser.firebaseId = profile.id
                    modelContext.insert(newUser)
                    existingUser = newUser
                    #if DEBUG
                    print("[SquadVM] Created local user for: \(profile.displayName)")
                    #endif
                }

                // Create membership if doesn't exist
                let hasMembership = squad.memberships?.contains(where: { $0.user?.firebaseId == profile.id }) ?? false
                if !hasMembership {
                    let membership = SquadMembership(user: existingUser, squad: squad)
                    modelContext.insert(membership)
                    #if DEBUG
                    print("[SquadVM] Created membership for: \(profile.displayName)")
                    #endif
                }
            }

            try modelContext.save()
            #if DEBUG
            print("[SquadVM] ✅ Registered \(profiles.count) squad members from CloudKit")
            #endif

            // Reload members to update the UI
            await loadMembers()

        } catch {
            #if DEBUG
            print("[SquadVM] Failed to fetch member profiles: \(error.localizedDescription)")
            #endif
        }
    }

    func leaveSquad() async throws {
        guard let squad = currentSquad,
              let userId = currentUserId else { return }

        isLoading = true
        defer { isLoading = false }

        // Remove from CloudKit
        if let cloudId = squad.firebaseId, cloudKit.isAvailable {
            try await cloudKit.leaveSquad(squadId: cloudId, userId: userId)
        }

        // Remove local membership
        if let memberships = squad.memberships {
            for membership in memberships {
                modelContext?.delete(membership)
            }
        }

        // Clean up chat messages for this squad
        if let modelContext = modelContext {
            let squadId = squad.id
            let messageDescriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate { $0.squadId == squadId }
            )
            if let messages = try? modelContext.fetch(messageDescriptor) {
                for message in messages {
                    modelContext.delete(message)
                }
            }
        }

        modelContext?.delete(squad)
        try modelContext?.save()

        currentSquad = nil
        members = []
        memberLocations = [:]
        peerTracker.clearAllPeers()
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.currentSquadId)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.currentJoinCode)

        // Stop mesh networking
        meshManager.stopAll()

        // Notify other components to clear squad-related data
        NotificationCenter.default.post(name: .didLeaveSquad, object: nil)
    }

    // MARK: - Member Operations

    func loadMembers() async {
        guard let squad = currentSquad,
              let memberships = squad.memberships else {
            members = []
            return
        }

        members = memberships.compactMap { $0.user }

        // Fetch remote locations if connected
        if let cloudId = squad.firebaseId, cloudKit.isAvailable {
            do {
                let locations = try await cloudKit.getSquadLocations(squadId: cloudId)
                for loc in locations {
                    // Validate coordinates before using
                    guard loc.latitude >= -90, loc.latitude <= 90,
                          loc.longitude >= -180, loc.longitude <= 180,
                          let userId = UUID(uuidString: loc.userId) else {
                        continue
                    }
                    let location = Location(
                        latitude: loc.latitude,
                        longitude: loc.longitude,
                        accuracy: 10,
                        timestamp: loc.timestamp,
                        source: .gateway
                    )
                    memberLocations[userId] = location
                }
            } catch {
                #if DEBUG
                print("[SquadVM] Failed to fetch remote locations: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func updateMemberLocation(_ userId: UUID, location: Location) {
        memberLocations[userId] = location

        if let member = members.first(where: { $0.id == userId }) {
            member.updateLocation(location)
            // Persist to database
            do {
                try modelContext?.save()
            } catch {
                #if DEBUG
                print("[SquadVM] Failed to persist location update: \(error)")
                #endif
            }
        }
    }

    // MARK: - QR Code

    func generateQRCodeData() -> Data? {
        guard let squad = currentSquad else { return nil }
        let urlString = "festivair://squad/\(squad.joinCode)"
        return urlString.data(using: .utf8)
    }

    // MARK: - Private Helpers

    private func loadCurrentSquad() {
        guard let modelContext = modelContext else { return }

        // Ensure we have a userId first - if not, don't load stale squad data
        let userId = getOrCreateUserId()

        let descriptor = FetchDescriptor<SquadMembership>(
            sortBy: [SortDescriptor(\.joinedAt, order: .reverse)]
        )

        do {
            let memberships = try modelContext.fetch(descriptor)
            if let membership = memberships.first, let squad = membership.squad {
                // Verify this membership belongs to the current user
                // If the userId in UserDefaults was reset, the SwiftData might have stale data
                let membershipUserId = membership.user?.firebaseId
                if membershipUserId != nil && membershipUserId != userId {
                    // Stale data from a different user session - clear it
                    #if DEBUG
                    print("[SquadVM] Clearing stale squad data (userId mismatch)")
                    #endif
                    clearStaleSquadData()
                    return
                }

                currentSquad = squad

                // Ensure joinCode is saved to UserDefaults (for mesh filtering)
                if UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.currentJoinCode) == nil {
                    UserDefaults.standard.set(squad.joinCode, forKey: Constants.UserDefaultsKeys.currentJoinCode)
                }

                // Configure mesh SYNCHRONOUSLY before any async work
                meshManager.configure(squadId: squad.id.uuidString, userId: userId)
                #if DEBUG
                print("[SquadVM] Configured mesh with squad")
                #endif

                Task {
                    await loadMembers()

                    // Fetch and register squad members from CloudKit
                    await refreshSquadMembers()
                }
            }
        } catch {
            #if DEBUG
            print("[SquadVM] Error loading squad: \(error)")
            #endif
        }
    }

    /// Clear stale squad data when userId doesn't match
    private func clearStaleSquadData() {
        guard let modelContext = modelContext else { return }

        // Delete all memberships
        let membershipDescriptor = FetchDescriptor<SquadMembership>()
        if let memberships = try? modelContext.fetch(membershipDescriptor) {
            for membership in memberships {
                modelContext.delete(membership)
            }
        }

        // Delete all squads
        let squadDescriptor = FetchDescriptor<Squad>()
        if let squads = try? modelContext.fetch(squadDescriptor) {
            for squad in squads {
                modelContext.delete(squad)
            }
        }

        try? modelContext.save()
        currentSquad = nil
        members = []
        memberLocations = [:]
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.currentSquadId)
        #if DEBUG
        print("[SquadVM] Cleared all stale squad data")
        #endif
    }

    /// Refresh squad members from CloudKit (called at app launch and pull-to-refresh)
    func refreshSquadMembers() async {
        guard let squad = currentSquad,
              squad.firebaseId != nil,  // Ensure we have a cloud squad
              let userId = currentUserId,
              cloudKit.isAvailable else {
            #if DEBUG
            print("[SquadVM] Cannot refresh - missing squad, cloudId, userId, or CloudKit unavailable")
            #endif
            return
        }

        #if DEBUG
        print("[SquadVM] Refreshing squad members from CloudKit...")
        #endif

        do {
            if let found = try await cloudKit.findSquad(byCode: squad.joinCode) {
                #if DEBUG
                print("[SquadVM] Found squad in CloudKit with \(found.memberIds.count) members")
                #endif
                await registerSquadMembers(memberIds: found.memberIds, excludingUserId: userId)
            } else {
                #if DEBUG
                print("[SquadVM] Squad not found in CloudKit during refresh")
                #endif
            }
        } catch {
            #if DEBUG
            print("[SquadVM] Failed to refresh members: \(error.localizedDescription)")
            #endif
        }
    }

    private func getOrCreateCurrentUser() async throws -> User? {
        guard let modelContext = modelContext else { return nil }

        let userId = currentUserId ?? UUID().uuidString
        if currentUserId == nil {
            UserDefaults.standard.set(userId, forKey: Constants.UserDefaultsKeys.userId)
        }

        // Try to find existing user
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.firebaseId == userId }
        )

        let existingUsers = try modelContext.fetch(descriptor)
        if let existing = existingUsers.first {
            return existing
        }

        // Create new user
        let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) ?? "Festival Fan"
        let emoji = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.emoji) ?? "🎧"

        let user = User(displayName: displayName, avatarEmoji: emoji)
        user.firebaseId = userId
        modelContext.insert(user)

        // Sync to CloudKit
        if cloudKit.isAvailable {
            try? await cloudKit.saveUser(id: userId, displayName: displayName, emoji: emoji)
        }

        return user
    }

    // MARK: - Mesh Network Handling

    private func setupMeshListener() {
        meshManager.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] envelope, _ in
                self?.handleMeshMessage(envelope)
            }
            .store(in: &cancellables)
    }

    /// Track if we're already refreshing to avoid duplicate calls
    private var isRefreshingMembers = false

    private func handleMeshMessage(_ envelope: Any) {
        guard let meshEnvelope = envelope as? MeshEnvelope else { return }

        // Forward ALL messages to PeerTracker so it can track online status
        peerTracker.handleMeshMessage(meshEnvelope, from: meshEnvelope.originPeerId)

        // Check if this message is from an unknown squad member - if so, refresh from CloudKit
        let senderUserId = meshEnvelope.message.userId
        let knownMemberIds = members.map { $0.firebaseId ?? "nil" }
        let isKnownMember = senderUserId != nil && members.contains(where: { $0.firebaseId == senderUserId })

        #if DEBUG
        print("[SquadVM] Mesh msg type=\(meshEnvelope.message.type), isKnown=\(isKnownMember), hasSquad=\(currentSquad != nil), isRefreshing=\(isRefreshingMembers)")
        #endif

        if senderUserId != nil,
           !isKnownMember,
           currentSquad != nil,
           !isRefreshingMembers {
            #if DEBUG
            print("[SquadVM] 🔄 Unknown member detected - refreshing from CloudKit")
            #endif
            isRefreshingMembers = true
            Task {
                await refreshSquadMembers()
                isRefreshingMembers = false
                #if DEBUG
                print("[SquadVM] ✅ Refresh complete, members now: \(self.members.count)")
                #endif
            }
        }

        switch meshEnvelope.message.type {
        case .locationUpdate:
            if let userIdString = meshEnvelope.message.userId,
               let userId = UUID(uuidString: userIdString),
               let locationPayload = meshEnvelope.message.location {
                let location = Location(
                    latitude: locationPayload.latitude,
                    longitude: locationPayload.longitude,
                    accuracy: locationPayload.accuracy,
                    timestamp: locationPayload.timestamp,
                    source: LocationSource(rawValue: locationPayload.source) ?? .mesh
                )
                updateMemberLocation(userId, location: location)
            }

        case .heartbeat:
            if let userIdString = meshEnvelope.message.userId,
               let userId = UUID(uuidString: userIdString),
               let batteryLevel = meshEnvelope.message.batteryLevel {
                if let member = members.first(where: { $0.id == userId }) {
                    member.batteryLevel = batteryLevel
                    member.hasService = meshEnvelope.message.hasService ?? false
                    member.lastSeen = Date()
                    // Persist heartbeat updates to database
                    do {
                        try modelContext?.save()
                    } catch {
                        #if DEBUG
                        print("[SquadVM] Failed to persist heartbeat: \(error)")
                        #endif
                    }
                }
            }

        default:
            break
        }
    }
}

// MARK: - Errors

enum SquadError: LocalizedError {
    case notAuthenticated
    case squadNotFound
    case squadFull
    case alreadyMember
    case tierLimitReached(currentLimit: Int, tier: PremiumTier)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in first"
        case .squadNotFound:
            return "Squad not found with that code"
        case .squadFull:
            return "This squad is full (max 12 members)"
        case .alreadyMember:
            return "You're already in this squad"
        case .tierLimitReached(let limit, let tier):
            if tier == .free {
                return "Free accounts can only join squads with up to \(limit) members. Upgrade to join larger groups!"
            } else if tier == .basic {
                return "Basic accounts can only join squads with up to \(limit) members. Upgrade to VIP for squads up to 12!"
            }
            return "This squad exceeds your membership limit of \(limit) members"
        case .networkError(let error):
            return error.localizedDescription
        }
    }

    var requiresUpgrade: Bool {
        if case .tierLimitReached = self {
            return true
        }
        return false
    }
}
