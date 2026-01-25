import Foundation
import SwiftUI
import SwiftData
import CoreLocation

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

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch Parties

    /// Fetch nearby parties based on user location
    func fetchNearbyParties(latitude: Double, longitude: Double, radiusKm: Double = 10.0) async {
        guard let context = modelContext else { return }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch from local database
            let descriptor = FetchDescriptor<Party>(
                predicate: #Predicate { party in
                    party.isActive == true
                },
                sortBy: [SortDescriptor(\.startTime)]
            )

            let allParties = try context.fetch(descriptor)

            // Filter by distance
            let userLocation = CLLocation(latitude: latitude, longitude: longitude)
            nearbyParties = allParties.filter { party in
                let partyLocation = CLLocation(latitude: party.latitude, longitude: party.longitude)
                let distanceKm = userLocation.distance(from: partyLocation) / 1000
                return distanceKm <= radiusKm
            }

            // Apply filters
            applyFilters()

            // Also try to sync from CloudKit
            await syncPartiesFromCloud(latitude: latitude, longitude: longitude, radiusKm: radiusKm)

        } catch {
            errorMessage = "Failed to fetch parties: \(error.localizedDescription)"
        }

        isLoading = false
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

        // Sync to CloudKit
        // TODO: await cloudKit.createParty(party)

        return party
    }

    // MARK: - Join / Leave Party

    func requestToJoin(party: Party, user: User) async throws {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

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
            throw PartyError.alreadyRequested
        }

        // Check capacity
        if party.isFull {
            throw PartyError.partyFull
        }

        let attendee = PartyAttendee(partyId: party.id, user: user)

        // For open parties, auto-approve
        if party.accessType == .open {
            attendee.status = .attending
            attendee.respondedAt = Date()
            party.currentAttendeeCount += 1
        }

        context.insert(attendee)
        try context.save()

        // Sync to CloudKit
        // TODO: await cloudKit.createAttendee(attendee)
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
            context.delete(attendee)
        }

        try context.save()
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

        // TODO: Send notification to user
        // TODO: Sync to CloudKit
    }

    func declineRequest(_ attendee: PartyAttendee) async throws {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

        attendee.status = .declined
        attendee.respondedAt = Date()

        try context.save()

        // TODO: Send notification to user
        // TODO: Sync to CloudKit
    }

    func endParty(_ party: Party) async throws {
        guard let context = modelContext else {
            throw PartyError.notConfigured
        }

        party.isActive = false
        party.endTime = Date()

        try context.save()
    }

    // MARK: - Filters

    func applyFilters() {
        var filtered = nearbyParties

        if let vibe = selectedVibe {
            filtered = filtered.filter { $0.vibe == vibe }
        }

        if let accessType = selectedAccessType {
            filtered = filtered.filter { $0.accessType == accessType }
        }

        if showActiveOnly {
            filtered = filtered.filter { $0.isActive && !$0.hasEnded }
        }

        nearbyParties = filtered
    }

    func clearFilters() {
        selectedVibe = nil
        selectedAccessType = nil
        showActiveOnly = true
    }

    // MARK: - CloudKit Sync

    private func syncPartiesFromCloud(latitude: Double, longitude: Double, radiusKm: Double) async {
        // TODO: Implement CloudKit sync for public parties
        // This would fetch parties from the public database
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
