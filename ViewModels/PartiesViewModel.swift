import Foundation
import SwiftUI
import SwiftData
import CoreLocation
import Combine

/// ViewModel for party discovery and management
@MainActor
final class PartiesViewModel: ObservableObject {

    // MARK: - Published State
    @Published var nearbyParties: [Party] = []
    @Published var myHostedParties: [Party] = []
    @Published var myAttendingParties: [Party] = []
    @Published var pendingRequests: [PartyAttendee] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    // Filters
    @Published var selectedVibe: PartyVibe?
    @Published var selectedAccessType: PartyAccessType?
    @Published var showActiveOnly = true

    // MARK: - Private
    private var modelContext: ModelContext?
    private let cloudKit = CloudKitService.shared
    private let subscriptionManager = SubscriptionManager.shared
    private var cancellables = Set<AnyCancellable>()

    // Store unfiltered parties to prevent data loss when filtering
    private var allNearbyParties: [Party] = []

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Clean up stale/ended parties on configure
        Task {
            await cleanupStaleParties()
        }
    }

    // MARK: - Fetch Parties

    /// Fetch nearby parties based on user location
    /// Default radius is 16km (~10 miles) - keeps parties local to event area
    func fetchNearbyParties(latitude: Double, longitude: Double, radiusKm: Double = 16.0) async {
        guard let context = modelContext else { return }

        isLoading = true
        errorMessage = nil
        print("[Parties] Fetching nearby parties at (\(latitude), \(longitude)) radius \(radiusKm)km")

        do {
            // Fetch from local database
            let descriptor = FetchDescriptor<Party>(
                predicate: #Predicate { party in
                    party.isActive == true
                },
                sortBy: [SortDescriptor(\.startTime)]
            )

            let allParties = try context.fetch(descriptor)
            print("[Parties] Found \(allParties.count) local parties")

            // Filter by distance
            let userLocation = CLLocation(latitude: latitude, longitude: longitude)
            allNearbyParties = allParties.filter { party in
                let partyLocation = CLLocation(latitude: party.latitude, longitude: party.longitude)
                let distanceKm = userLocation.distance(from: partyLocation) / 1000
                return distanceKm <= radiusKm
            }

            print("[Parties] \(allNearbyParties.count) parties within radius")

            // Apply filters (uses allNearbyParties as source)
            applyFilters()

            // Sync from CloudKit and fetch real attendee counts
            await syncPartiesFromCloud(latitude: latitude, longitude: longitude, radiusKm: radiusKm)

            // Refresh attendee counts from CloudKit
            await refreshAttendeeCounts()

        } catch {
            errorMessage = "Failed to fetch parties: \(error.localizedDescription)"
            print("[Parties] ❌ Error: \(error)")
        }

        isLoading = false
    }

    /// Refresh attendee counts for all nearby parties from CloudKit
    private func refreshAttendeeCounts() async {
        guard cloudKit.isAvailable else {
            print("[Parties] CloudKit not available for attendee refresh")
            return
        }

        print("[Parties] Refreshing attendee counts from CloudKit...")

        for party in allNearbyParties {
            do {
                let attendees = try await cloudKit.fetchPartyAttendees(partyId: party.id.uuidString)
                let approvedCount = attendees.filter { $0.status == "attending" || $0.status == "approved" }.count

                if party.currentAttendeeCount != approvedCount {
                    print("[Parties] Updating party '\(party.name)' count: \(party.currentAttendeeCount) -> \(approvedCount)")
                    party.currentAttendeeCount = approvedCount
                    try? modelContext?.save()
                }
            } catch {
                print("[Parties] Failed to fetch attendees for party \(party.id): \(error)")
            }
        }

        // Update UI
        applyFilters()
    }

    /// Fetch parties hosted by current user
    func fetchMyHostedParties(userId: String) async {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<Party>(
                predicate: #Predicate { party in
                    party.hostUserId == userId
                },
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )

            myHostedParties = try context.fetch(descriptor)
        } catch {
            errorMessage = "Failed to fetch hosted parties: \(error.localizedDescription)"
        }
    }

    /// Fetch parties user is attending
    func fetchMyAttendingParties(userId: String) async {
        guard let context = modelContext else { return }

        do {
            // First get attendee records for this user
            let attendeeDescriptor = FetchDescriptor<PartyAttendee>(
                predicate: #Predicate { attendee in
                    attendee.userId == userId &&
                    (attendee.statusRawValue == "approved" || attendee.statusRawValue == "attending")
                }
            )

            let attendees = try context.fetch(attendeeDescriptor)
            let partyIds = attendees.map { $0.partyId }

            // Then fetch those parties
            let partyDescriptor = FetchDescriptor<Party>(
                sortBy: [SortDescriptor(\.startTime)]
            )

            let allParties = try context.fetch(partyDescriptor)
            myAttendingParties = allParties.filter { partyIds.contains($0.id) }

        } catch {
            errorMessage = "Failed to fetch attending parties: \(error.localizedDescription)"
        }
    }

    /// Fetch pending requests for host's parties
    func fetchPendingRequests(hostUserId: String) async {
        guard let context = modelContext else { return }

        do {
            // Get all party IDs for this host
            let partyDescriptor = FetchDescriptor<Party>(
                predicate: #Predicate { party in
                    party.hostUserId == hostUserId
                }
            )

            let hostedParties = try context.fetch(partyDescriptor)
            let partyIds = hostedParties.map { $0.id }

            // Get pending requests for those parties
            let attendeeDescriptor = FetchDescriptor<PartyAttendee>(
                predicate: #Predicate { attendee in
                    attendee.statusRawValue == "requested"
                },
                sortBy: [SortDescriptor(\.requestedAt, order: .reverse)]
            )

            let allRequests = try context.fetch(attendeeDescriptor)
            pendingRequests = allRequests.filter { partyIds.contains($0.partyId) }

        } catch {
            errorMessage = "Failed to fetch requests: \(error.localizedDescription)"
        }
    }

    // MARK: - Create Party

    func createParty(
        name: String,
        description: String?,
        latitude: Double,
        longitude: Double,
        locationName: String?,
        startTime: Date,
        endTime: Date?,
        maxAttendees: Int?,
        vibe: PartyVibe,
        accessType: PartyAccessType,
        hostUser: User
    ) async throws -> Party {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

        // Check if user can create this type of party
        if accessType.requiresVIP && !subscriptionManager.canHostExclusiveParties {
            throw PartyError.vipRequired
        }

        let party = Party(
            name: name,
            hostUserId: hostUser.id.uuidString,
            hostDisplayName: hostUser.displayName,
            description: description,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            startTime: startTime,
            endTime: endTime,
            maxAttendees: maxAttendees,
            vibe: vibe,
            accessType: accessType
        )

        context.insert(party)
        try context.save()

        // Add to local lists immediately so it shows up right away
        allNearbyParties.insert(party, at: 0)
        nearbyParties.insert(party, at: 0)
        myHostedParties.insert(party, at: 0)

        // Sync to CloudKit in background
        Task {
            await syncPartyToCloud(party)
        }

        return party
    }

    // MARK: - Join / Leave Party

    func requestToJoin(party: Party, user: User) async throws {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

        print("[Parties] User \(user.displayName) requesting to join party '\(party.name)'")

        // Check if already requested or attending
        let partyId = party.id
        let userIdString = user.id.uuidString
        let existingDescriptor = FetchDescriptor<PartyAttendee>(
            predicate: #Predicate { attendee in
                attendee.partyId == partyId && attendee.userId == userIdString
            }
        )

        let existing = try context.fetch(existingDescriptor)
        if !existing.isEmpty {
            print("[Parties] ⚠️ User already requested/attending this party")
            throw PartyError.alreadyRequested
        }

        // Check capacity
        if party.isFull {
            print("[Parties] ⚠️ Party is full")
            throw PartyError.partyFull
        }

        let attendee = PartyAttendee(partyId: party.id, user: user)

        // For open parties, auto-approve
        if party.accessType == .open {
            attendee.status = .attending
            attendee.respondedAt = Date()
            party.currentAttendeeCount += 1
            print("[Parties] ✅ Auto-approved for open party. Count now: \(party.currentAttendeeCount)")
        }

        context.insert(attendee)
        try context.save()

        // Sync attendee to CloudKit
        await syncAttendeeToCloud(attendee, partyId: party.id.uuidString)

        // CRITICAL: Also sync the updated party count to CloudKit
        if cloudKit.isAvailable {
            do {
                try await cloudKit.updateParty(party)
                print("[Parties] ✅ Synced updated party count to CloudKit: \(party.currentAttendeeCount)")
            } catch {
                print("[Parties] ❌ Failed to sync party count: \(error)")
            }
        }
    }

    func leaveParty(party: Party, userId: String) async throws {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

        let partyId = party.id
        let descriptor = FetchDescriptor<PartyAttendee>(
            predicate: #Predicate { attendee in
                attendee.partyId == partyId && attendee.userId == userId
            }
        )

        let attendees = try context.fetch(descriptor)
        for attendee in attendees {
            if attendee.isApproved {
                party.currentAttendeeCount = max(0, party.currentAttendeeCount - 1)
            }

            // Sync deletion to CloudKit
            if let recordId = attendee.cloudKitRecordId, cloudKit.isAvailable {
                Task {
                    do {
                        try await cloudKit.deleteAttendee(attendeeId: recordId)
                    } catch {
                        print("[Parties] Failed to delete attendee from CloudKit: \(error)")
                    }
                }
            }

            context.delete(attendee)
        }

        try context.save()

        // Update party attendee count in CloudKit
        if cloudKit.isAvailable {
            Task {
                do {
                    try await cloudKit.updateParty(party)
                } catch {
                    print("[Parties] Failed to update party count in CloudKit: \(error)")
                }
            }
        }
    }

    // MARK: - Host Actions

    func approveRequest(_ attendee: PartyAttendee, party: Party) async throws {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

        attendee.status = .approved
        attendee.respondedAt = Date()
        party.currentAttendeeCount += 1

        try context.save()

        // Sync status to CloudKit
        if let recordId = attendee.cloudKitRecordId, cloudKit.isAvailable {
            do {
                try await cloudKit.updateAttendeeStatus(attendeeId: recordId, status: "approved")
            } catch {
                print("[Parties] Failed to sync approval to CloudKit: \(error)")
                // Note: Local update succeeded, cloud sync will retry next time
            }
        }
    }

    func declineRequest(_ attendee: PartyAttendee) async throws {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

        attendee.status = .declined
        attendee.respondedAt = Date()

        try context.save()

        // Sync status to CloudKit
        if let recordId = attendee.cloudKitRecordId, cloudKit.isAvailable {
            do {
                try await cloudKit.updateAttendeeStatus(attendeeId: recordId, status: "declined")
            } catch {
                print("[Parties] Failed to sync decline to CloudKit: \(error)")
                // Note: Local update succeeded, cloud sync will retry next time
            }
        }
    }

    func endParty(_ party: Party) async throws {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

        party.isActive = false
        party.endTime = Date()

        try context.save()
    }

    /// Delete a party completely (host only)
    func deleteParty(_ party: Party, userId: String) async throws {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

        // Verify user is the host
        guard party.hostUserId == userId else {
            throw PartyError.unauthorized
        }

        print("[Parties] Deleting party '\(party.name)' by host \(userId)")

        // Delete from CloudKit first
        if cloudKit.isAvailable {
            do {
                try await cloudKit.deleteParty(partyId: party.id.uuidString)
            } catch {
                print("[Parties] ❌ Failed to delete from CloudKit: \(error)")
                // Continue with local deletion even if cloud fails
            }
        }

        // Delete all attendee records for this party
        let partyId = party.id
        let attendeeDescriptor = FetchDescriptor<PartyAttendee>(
            predicate: #Predicate { $0.partyId == partyId }
        )
        if let attendees = try? context.fetch(attendeeDescriptor) {
            for attendee in attendees {
                context.delete(attendee)
            }
        }

        // Remove from local lists
        allNearbyParties.removeAll { $0.id == party.id }
        nearbyParties.removeAll { $0.id == party.id }
        myHostedParties.removeAll { $0.id == party.id }

        // Delete the party itself
        context.delete(party)
        try context.save()

        print("[Parties] ✅ Party deleted successfully")
    }

    // MARK: - Filters

    func applyFilters() {
        // Always filter from the original unfiltered list to prevent data loss
        var filtered = allNearbyParties

        // ALWAYS filter out ended parties - they should never show
        filtered = filtered.filter { !$0.hasEnded }

        if let vibe = selectedVibe {
            filtered = filtered.filter { $0.vibe == vibe }
        }

        if let accessType = selectedAccessType {
            filtered = filtered.filter { $0.accessType == accessType }
        }

        if showActiveOnly {
            filtered = filtered.filter { $0.isActive }
        }

        nearbyParties = filtered
    }

    func clearFilters() {
        selectedVibe = nil
        selectedAccessType = nil
        showActiveOnly = true
        // Restore all parties when clearing filters
        nearbyParties = allNearbyParties
    }

    // MARK: - CloudKit Sync

    private func syncPartiesFromCloud(latitude: Double, longitude: Double, radiusKm: Double) async {
        guard cloudKit.isAvailable, let context = modelContext else {
            print("[Parties] CloudKit not available for party sync")
            return
        }

        print("[Parties] Syncing parties from CloudKit...")

        do {
            let cloudParties = try await cloudKit.fetchPartiesNear(
                latitude: latitude,
                longitude: longitude,
                radiusKm: radiusKm
            )

            print("[Parties] Found \(cloudParties.count) parties in CloudKit")

            // Merge cloud parties with local
            for record in cloudParties {
                // Check if party already exists locally
                let partyId = UUID(uuidString: record.id) ?? UUID()
                let descriptor = FetchDescriptor<Party>(
                    predicate: #Predicate { $0.id == partyId }
                )

                let existing = try? context.fetch(descriptor)
                if let existingParty = existing?.first {
                    // Update existing party with cloud data
                    existingParty.currentAttendeeCount = record.currentAttendeeCount
                    existingParty.isActive = record.isActive
                    print("[Parties] Updated existing party '\(record.name)' count: \(record.currentAttendeeCount)")
                } else {
                    // Create new local party from cloud
                    let party = Party(
                        id: partyId,
                        name: record.name,
                        hostUserId: record.hostUserId,
                        hostDisplayName: record.hostDisplayName,
                        description: record.description,
                        latitude: record.latitude,
                        longitude: record.longitude,
                        locationName: record.locationName,
                        startTime: record.startTime,
                        endTime: record.endTime,
                        maxAttendees: record.maxAttendees,
                        vibe: PartyVibe(rawValue: record.vibe) ?? .chill,
                        accessType: PartyAccessType(rawValue: record.accessType) ?? .open
                    )
                    party.isLocationHidden = record.isLocationHidden
                    party.currentAttendeeCount = record.currentAttendeeCount
                    party.isActive = record.isActive
                    party.cloudKitRecordId = record.id

                    context.insert(party)
                    print("[Parties] Created new party from cloud: '\(record.name)' with \(record.currentAttendeeCount) attendees")
                }
            }

            try context.save()

            // Refresh the displayed list
            let userLocation = CLLocation(latitude: latitude, longitude: longitude)
            let descriptor = FetchDescriptor<Party>(
                predicate: #Predicate { $0.isActive == true },
                sortBy: [SortDescriptor(\.startTime)]
            )
            let allParties = try context.fetch(descriptor)
            allNearbyParties = allParties.filter { party in
                let partyLocation = CLLocation(latitude: party.latitude, longitude: party.longitude)
                return userLocation.distance(from: partyLocation) / 1000 <= radiusKm
            }
            applyFilters()

            print("[Parties] ✅ Sync complete. Displaying \(nearbyParties.count) parties")

        } catch {
            print("[Parties] ❌ CloudKit sync error: \(error)")
        }
    }

    /// Sync a created party to CloudKit
    private func syncPartyToCloud(_ party: Party) async {
        guard cloudKit.isAvailable else { return }

        do {
            let recordId = try await cloudKit.createParty(party)
            party.cloudKitRecordId = recordId
            try modelContext?.save()
        } catch {
            print("[Parties] Failed to sync party to cloud: \(error)")
        }
    }

    /// Sync attendee request to CloudKit
    private func syncAttendeeToCloud(_ attendee: PartyAttendee, partyId: String) async {
        guard cloudKit.isAvailable else {
            print("[Parties] CloudKit not available for attendee sync")
            return
        }

        print("[Parties] Syncing attendee '\(attendee.displayName)' to CloudKit...")

        do {
            let recordId = try await cloudKit.createAttendeeRequest(partyId: partyId, attendee: attendee)
            attendee.cloudKitRecordId = recordId
            try modelContext?.save()
            print("[Parties] ✅ Attendee synced with recordId: \(recordId)")
        } catch {
            print("[Parties] ❌ Failed to sync attendee to cloud: \(error)")
        }
    }

    /// Check if current user is attending a party
    func isUserAttending(party: Party, userId: String) -> Bool {
        guard let context = modelContext else { return false }

        let partyId = party.id
        let descriptor = FetchDescriptor<PartyAttendee>(
            predicate: #Predicate { attendee in
                attendee.partyId == partyId &&
                attendee.userId == userId &&
                (attendee.statusRawValue == "attending" || attendee.statusRawValue == "approved")
            }
        )

        let attendees = try? context.fetch(descriptor)
        return !(attendees?.isEmpty ?? true)
    }

    // MARK: - Cleanup

    /// Clean up stale parties (ended or without end time)
    /// Call this on app launch to remove old test/orphaned parties
    func cleanupStaleParties() async {
        guard let context = modelContext else { return }

        print("[Parties] 🧹 Running stale party cleanup...")

        do {
            let descriptor = FetchDescriptor<Party>()
            let allParties = try context.fetch(descriptor)

            var deletedCount = 0

            for party in allParties {
                // Delete if:
                // 1. Party has ended (isActive=false or past endTime)
                // 2. Party has no endTime set (legacy party that could run forever)
                // 3. Party ended more than 24 hours ago
                let shouldDelete: Bool

                if party.endTime == nil {
                    // Legacy party with no end time - delete it
                    shouldDelete = true
                    print("[Parties] Deleting party '\(party.name)' - no end time set")
                } else if party.hasEnded {
                    // Check if it ended more than 24 hours ago
                    if let endTime = party.endTime, Date().timeIntervalSince(endTime) > 86400 {
                        shouldDelete = true
                        print("[Parties] Deleting party '\(party.name)' - ended 24+ hours ago")
                    } else {
                        shouldDelete = false
                    }
                } else {
                    shouldDelete = false
                }

                if shouldDelete {
                    // Try to delete from CloudKit too
                    if cloudKit.isAvailable {
                        try? await cloudKit.deleteParty(partyId: party.id.uuidString)
                    }

                    // Delete attendees
                    let partyId = party.id
                    let attendeeDescriptor = FetchDescriptor<PartyAttendee>(
                        predicate: #Predicate { $0.partyId == partyId }
                    )
                    if let attendees = try? context.fetch(attendeeDescriptor) {
                        for attendee in attendees {
                            context.delete(attendee)
                        }
                    }

                    context.delete(party)
                    deletedCount += 1
                }
            }

            if deletedCount > 0 {
                try context.save()
                print("[Parties] ✅ Cleaned up \(deletedCount) stale parties")
            } else {
                print("[Parties] ✅ No stale parties to clean up")
            }
        } catch {
            print("[Parties] ❌ Cleanup failed: \(error)")
        }
    }
}

// MARK: - Errors

enum PartyError: LocalizedError {
    case notConfigured
    case vipRequired
    case alreadyRequested
    case partyFull
    case notFound
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Party system not configured"
        case .vipRequired: return "VIP subscription required to create exclusive parties"
        case .alreadyRequested: return "You've already requested to join this party"
        case .partyFull: return "This party is at capacity"
        case .notFound: return "Party not found"
        case .unauthorized: return "You don't have permission to do that"
        }
    }
}
