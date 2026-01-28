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

    func createSquad(name: String) async throws {
        guard let userId = currentUserId else {
            throw SquadError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        let joinCode = Squad.generateJoinCode()

        // Create local squad
        let squad = Squad(name: name, joinCode: joinCode)

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
                let cloudId = try await cloudKit.createSquad(name: name, joinCode: joinCode, creatorId: userId)
                squad.firebaseId = cloudId // Reusing field for CloudKit ID
                try modelContext?.save()
            } catch {
                // CloudKit sync failed (e.g., schema not deployed) - continue with local-only squad
                print("[Squad] CloudKit sync failed, continuing with local squad: \(error.localizedDescription)")
            }
        }

        currentSquad = squad
        UserDefaults.standard.set(squad.id.uuidString, forKey: Constants.UserDefaultsKeys.currentSquadId)
        await loadMembers()

        // Configure mesh networking
        meshManager.configure(squadId: squad.id.uuidString, userId: userId)
    }

    func joinSquad(code: String) async throws {
        guard let userId = currentUserId else {
            throw SquadError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        // Try CloudKit first (optional - works offline/local-only)
        var squadName = "Squad"
        var cloudSquadId: String?
        var existingMemberIds: [String] = []

        if cloudKit.isAvailable {
            do {
                if let found = try await cloudKit.findSquad(byCode: code) {
                    squadName = found.name
                    cloudSquadId = found.id
                    existingMemberIds = found.memberIds
                    let memberCount = found.memberIds.count

                    // Check tier-based member limit
                    let userLimit = subscriptionManager.squadLimit
                    if memberCount >= userLimit {
                        throw SquadError.tierLimitReached(currentLimit: userLimit, tier: subscriptionManager.currentTier)
                    }

                    try await cloudKit.joinSquad(squadId: found.id, userId: userId)
                }
            } catch let error as SquadError {
                // Re-throw squad-specific errors (like tier limit)
                throw error
            } catch {
                // CloudKit sync failed - continue with local squad
                print("[Squad] CloudKit lookup failed, continuing with local squad: \(error.localizedDescription)")
            }
        }

        // Check for existing local squad with this join code (avoid duplicates)
        let existingSquad: Squad?
        if let modelContext = modelContext {
            let joinCode = code
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
            squad = Squad(name: squadName, joinCode: code)
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
        await loadMembers()

        // Fetch and register other squad members from CloudKit
        await registerSquadMembers(memberIds: existingMemberIds, excludingUserId: userId)

        // Configure mesh networking
        meshManager.configure(squadId: squad.id.uuidString, userId: userId)
    }

    /// Fetch member profiles from CloudKit and register them with PeerTracker
    private func registerSquadMembers(memberIds: [String], excludingUserId: String) async {
        guard cloudKit.isAvailable else { return }

        let otherMemberIds = memberIds.filter { $0 != excludingUserId }
        guard !otherMemberIds.isEmpty else { return }

        do {
            let profiles = try await cloudKit.getSquadMemberProfiles(memberIds: otherMemberIds)
            for profile in profiles {
                peerTracker.registerRemoteMember(
                    id: profile.id,
                    displayName: profile.displayName,
                    emoji: profile.emoji
                )
            }
            print("[Squad] Registered \(profiles.count) squad members from CloudKit")
        } catch {
            print("[Squad] Failed to fetch member profiles: \(error.localizedDescription)")
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
            let locations = try? await cloudKit.getSquadLocations(squadId: cloudId)
            for loc in locations ?? [] {
                if let userId = UUID(uuidString: loc.userId) {
                    let location = Location(
                        latitude: loc.latitude,
                        longitude: loc.longitude,
                        accuracy: 10,
                        timestamp: loc.timestamp,
                        source: .gateway
                    )
                    memberLocations[userId] = location
                }
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
                print("[SquadVM] Failed to persist location update: \(error)")
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

        let descriptor = FetchDescriptor<SquadMembership>(
            sortBy: [SortDescriptor(\.joinedAt, order: .reverse)]
        )

        do {
            let memberships = try modelContext.fetch(descriptor)
            if let membership = memberships.first, let squad = membership.squad {
                currentSquad = squad
                Task {
                    await loadMembers()
                    if let userId = currentUserId {
                        meshManager.configure(squadId: squad.id.uuidString, userId: userId)

                        // Fetch and register squad members from CloudKit
                        await refreshSquadMembers()
                    }
                }
            }
        } catch {
            print("[SquadVM] Error loading squad: \(error)")
        }
    }

    /// Refresh squad members from CloudKit (called at app launch and pull-to-refresh)
    func refreshSquadMembers() async {
        guard let squad = currentSquad,
              let cloudId = squad.firebaseId,
              let userId = currentUserId,
              cloudKit.isAvailable else { return }

        do {
            if let found = try await cloudKit.findSquad(byCode: squad.joinCode) {
                await registerSquadMembers(memberIds: found.memberIds, excludingUserId: userId)
            }
        } catch {
            print("[Squad] Failed to refresh members: \(error.localizedDescription)")
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

    private func handleMeshMessage(_ envelope: Any) {
        guard let meshEnvelope = envelope as? MeshEnvelope else { return }

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
                        print("[SquadVM] Failed to persist heartbeat: \(error)")
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
