import Foundation
import CloudKit
import CoreLocation

/// Handles iCloud sync for squad data - no Firebase needed
final class CloudKitService: ObservableObject {

    // MARK: - Singleton
    static let shared = CloudKitService()

    // MARK: - CloudKit Configuration
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    // MARK: - Record Types
    private enum RecordType {
        static let user = "User"
        static let squad = "Squad"
        static let location = "Location"
        static let message = "Message"
        static let party = "Party"
        static let partyAttendee = "PartyAttendee"
    }

    // MARK: - Public Database (for parties)
    private let publicDatabase: CKDatabase

    // MARK: - Zone
    private let zoneID = CKRecordZone.ID(zoneName: "FestivAirZone", ownerName: CKCurrentUserDefaultName)
    private var zone: CKRecordZone?

    // MARK: - Published State
    @Published private(set) var isAvailable = false
    @Published private(set) var currentUserRecordID: CKRecord.ID?
    @Published private(set) var lastError: Error?

    // MARK: - Init
    private init() {
        // Use default container (configure in entitlements)
        container = CKContainer.default()
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
        publicDatabase = container.publicCloudDatabase

        Task {
            await checkAccountStatus()
            await createZoneIfNeeded()
        }
    }

    // MARK: - Account Status

    private func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            await MainActor.run {
                isAvailable = status == .available
            }

            if status == .available {
                let userID = try await container.userRecordID()
                await MainActor.run {
                    currentUserRecordID = userID
                }
            }
        } catch {
            await MainActor.run {
                lastError = error
                isAvailable = false
            }
        }
    }

    private func createZoneIfNeeded() async {
        do {
            let newZone = CKRecordZone(zoneID: zoneID)
            zone = try await privateDatabase.save(newZone)
        } catch {
            // Zone might already exist, that's fine
            if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                zone = CKRecordZone(zoneID: zoneID)
            } else {
                print("[CloudKit] Zone creation error: \(error)")
                zone = CKRecordZone(zoneID: zoneID)
            }
        }
    }

    // MARK: - User Operations

    func saveUser(id: String, displayName: String, emoji: String) async throws {
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.user, recordID: recordID)

        record["displayName"] = displayName
        record["emoji"] = emoji
        record["lastUpdated"] = Date()

        try await privateDatabase.save(record)
    }

    func getUser(id: String) async throws -> (displayName: String, emoji: String)? {
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)

        do {
            let record = try await privateDatabase.record(for: recordID)
            let displayName = record["displayName"] as? String ?? "Unknown"
            let emoji = record["emoji"] as? String ?? "🎧"
            return (displayName, emoji)
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return nil
            }
            throw error
        }
    }

    // MARK: - Squad Operations

    func createSquad(name: String, joinCode: String, creatorId: String) async throws -> String {
        let squadId = UUID().uuidString
        let recordID = CKRecord.ID(recordName: squadId, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.squad, recordID: recordID)

        record["name"] = name
        record["joinCode"] = joinCode
        record["memberIds"] = [creatorId]
        record["createdAt"] = Date()

        try await privateDatabase.save(record)
        return squadId
    }

    func findSquad(byCode code: String) async throws -> (id: String, name: String, memberIds: [String])? {
        let predicate = NSPredicate(format: "joinCode == %@", code)
        let query = CKQuery(recordType: RecordType.squad, predicate: predicate)

        let results = try await privateDatabase.records(matching: query)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                let id = record.recordID.recordName
                let name = record["name"] as? String ?? "Squad"
                let memberIds = record["memberIds"] as? [String] ?? []
                return (id, name, memberIds)
            }
        }

        return nil
    }

    func joinSquad(squadId: String, userId: String) async throws {
        let recordID = CKRecord.ID(recordName: squadId, zoneID: zoneID)
        let record = try await privateDatabase.record(for: recordID)

        var memberIds = record["memberIds"] as? [String] ?? []
        if !memberIds.contains(userId) {
            memberIds.append(userId)
            record["memberIds"] = memberIds
            try await privateDatabase.save(record)
        }
    }

    func leaveSquad(squadId: String, userId: String) async throws {
        let recordID = CKRecord.ID(recordName: squadId, zoneID: zoneID)
        let record = try await privateDatabase.record(for: recordID)

        var memberIds = record["memberIds"] as? [String] ?? []
        memberIds.removeAll { $0 == userId }
        record["memberIds"] = memberIds
        try await privateDatabase.save(record)
    }

    // MARK: - Location Operations

    func updateLocation(squadId: String, userId: String, latitude: Double, longitude: Double, accuracy: Double) async throws {
        let recordName = "\(squadId)_\(userId)"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)

        // Try to fetch existing record or create new one
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: RecordType.location, recordID: recordID)
        }

        record["squadId"] = squadId
        record["userId"] = userId
        record["latitude"] = latitude
        record["longitude"] = longitude
        record["accuracy"] = accuracy
        record["timestamp"] = Date()

        try await privateDatabase.save(record)
    }

    func getSquadLocations(squadId: String) async throws -> [(userId: String, latitude: Double, longitude: Double, timestamp: Date)] {
        let predicate = NSPredicate(format: "squadId == %@", squadId)
        let query = CKQuery(recordType: RecordType.location, predicate: predicate)

        let results = try await privateDatabase.records(matching: query)

        var locations: [(userId: String, latitude: Double, longitude: Double, timestamp: Date)] = []

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                let userId = record["userId"] as? String ?? ""
                let lat = record["latitude"] as? Double ?? 0
                let lon = record["longitude"] as? Double ?? 0
                let timestamp = record["timestamp"] as? Date ?? Date()
                locations.append((userId, lat, lon, timestamp))
            }
        }

        return locations
    }

    // MARK: - Message Operations

    func sendMessage(squadId: String, senderId: String, senderName: String, text: String) async throws -> String {
        let messageId = UUID().uuidString
        let recordID = CKRecord.ID(recordName: messageId, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.message, recordID: recordID)

        record["squadId"] = squadId
        record["senderId"] = senderId
        record["senderName"] = senderName
        record["text"] = text
        record["timestamp"] = Date()

        try await privateDatabase.save(record)
        return messageId
    }

    func getMessages(squadId: String, since: Date? = nil) async throws -> [(id: String, senderId: String, senderName: String, text: String, timestamp: Date)] {
        var predicateFormat = "squadId == %@"
        var arguments: [Any] = [squadId]

        if let since = since {
            predicateFormat += " AND timestamp > %@"
            arguments.append(since)
        }

        let predicate = NSPredicate(format: predicateFormat, argumentArray: arguments)
        let query = CKQuery(recordType: RecordType.message, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        let results = try await privateDatabase.records(matching: query)

        var messages: [(id: String, senderId: String, senderName: String, text: String, timestamp: Date)] = []

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                let id = record.recordID.recordName
                let senderId = record["senderId"] as? String ?? ""
                let senderName = record["senderName"] as? String ?? "Unknown"
                let text = record["text"] as? String ?? ""
                let timestamp = record["timestamp"] as? Date ?? Date()
                messages.append((id, senderId, senderName, text, timestamp))
            }
        }

        return messages
    }

    // MARK: - Profile Photo Operations

    /// Upload a profile photo and return the asset ID
    func uploadProfilePhoto(_ imageData: Data, userId: String) async throws -> String {
        let recordID = CKRecord.ID(recordName: userId, zoneID: zoneID)

        // Fetch existing user record or create new one
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: RecordType.user, recordID: recordID)
        }

        // Create temp file for asset
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(userId)_profile.jpg")
        try imageData.write(to: tempFile)

        // Create CKAsset
        let asset = CKAsset(fileURL: tempFile)
        record["profilePhoto"] = asset
        record["lastUpdated"] = Date()

        // Save record
        let savedRecord = try await privateDatabase.save(record)

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempFile)

        // Return asset identifier (use record name as the ID)
        return savedRecord.recordID.recordName
    }

    /// Get the URL for a profile photo asset
    func getProfilePhotoURL(_ assetId: String) async throws -> URL? {
        let recordID = CKRecord.ID(recordName: assetId, zoneID: zoneID)

        do {
            let record = try await privateDatabase.record(for: recordID)
            if let asset = record["profilePhoto"] as? CKAsset {
                return asset.fileURL
            }
        } catch {
            print("[CloudKit] Failed to get profile photo: \(error)")
        }

        return nil
    }

    /// Update user profile fields
    func updateUserProfile(
        userId: String,
        displayName: String? = nil,
        emoji: String? = nil,
        bio: String? = nil,
        instagramHandle: String? = nil,
        instagramFollowers: Int? = nil,
        tiktokHandle: String? = nil,
        tiktokFollowers: Int? = nil,
        verificationStatus: String? = nil,
        badges: [String]? = nil,
        premiumTier: String? = nil,
        premiumExpiresAt: Date? = nil
    ) async throws {
        let recordID = CKRecord.ID(recordName: userId, zoneID: zoneID)

        // Fetch existing user record or create new one
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: RecordType.user, recordID: recordID)
        }

        // Update fields if provided
        if let displayName = displayName {
            record["displayName"] = displayName
        }
        if let emoji = emoji {
            record["emoji"] = emoji
        }
        if let bio = bio {
            record["bio"] = bio
        }
        if let instagramHandle = instagramHandle {
            record["instagramHandle"] = instagramHandle
        }
        if let instagramFollowers = instagramFollowers {
            record["instagramFollowers"] = instagramFollowers
        }
        if let tiktokHandle = tiktokHandle {
            record["tiktokHandle"] = tiktokHandle
        }
        if let tiktokFollowers = tiktokFollowers {
            record["tiktokFollowers"] = tiktokFollowers
        }
        if let verificationStatus = verificationStatus {
            record["verificationStatus"] = verificationStatus
        }
        if let badges = badges {
            record["badges"] = badges
        }
        if let premiumTier = premiumTier {
            record["premiumTier"] = premiumTier
        }
        if let premiumExpiresAt = premiumExpiresAt {
            record["premiumExpiresAt"] = premiumExpiresAt
        }

        record["lastUpdated"] = Date()
        try await privateDatabase.save(record)
    }

    /// Fetch a user's full profile from CloudKit
    func getUserProfile(userId: String) async throws -> (
        displayName: String,
        emoji: String,
        bio: String?,
        instagramHandle: String?,
        instagramFollowers: Int?,
        tiktokHandle: String?,
        tiktokFollowers: Int?,
        verificationStatus: String?,
        badges: [String]?,
        premiumTier: String?,
        premiumExpiresAt: Date?,
        profilePhotoURL: URL?
    )? {
        let recordID = CKRecord.ID(recordName: userId, zoneID: zoneID)

        do {
            let record = try await privateDatabase.record(for: recordID)

            let displayName = record["displayName"] as? String ?? "Unknown"
            let emoji = record["emoji"] as? String ?? "🎧"
            let bio = record["bio"] as? String
            let instagramHandle = record["instagramHandle"] as? String
            let instagramFollowers = record["instagramFollowers"] as? Int
            let tiktokHandle = record["tiktokHandle"] as? String
            let tiktokFollowers = record["tiktokFollowers"] as? Int
            let verificationStatus = record["verificationStatus"] as? String
            let badges = record["badges"] as? [String]
            let premiumTier = record["premiumTier"] as? String
            let premiumExpiresAt = record["premiumExpiresAt"] as? Date
            let profilePhotoURL = (record["profilePhoto"] as? CKAsset)?.fileURL

            return (
                displayName,
                emoji,
                bio,
                instagramHandle,
                instagramFollowers,
                tiktokHandle,
                tiktokFollowers,
                verificationStatus,
                badges,
                premiumTier,
                premiumExpiresAt,
                profilePhotoURL
            )
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return nil
            }
            throw error
        }
    }

    // MARK: - Party Operations (Public Database)

    /// Create a party in the public database for discovery
    func createParty(_ party: Party) async throws -> String {
        let recordID = CKRecord.ID(recordName: party.id.uuidString)
        let record = CKRecord(recordType: RecordType.party, recordID: recordID)

        record["name"] = party.name
        record["hostUserId"] = party.hostUserId
        record["hostDisplayName"] = party.hostDisplayName
        record["description"] = party.partyDescription
        record["latitude"] = party.latitude
        record["longitude"] = party.longitude
        record["locationName"] = party.locationName
        record["isLocationHidden"] = party.isLocationHidden
        record["startTime"] = party.startTime
        record["endTime"] = party.endTime
        record["maxAttendees"] = party.maxAttendees
        record["currentAttendeeCount"] = party.currentAttendeeCount
        record["isActive"] = party.isActive
        record["vibe"] = party.vibeRawValue
        record["accessType"] = party.accessTypeRawValue
        record["createdAt"] = party.createdAt

        let savedRecord = try await publicDatabase.save(record)
        return savedRecord.recordID.recordName
    }

    /// Fetch parties near a location from public database
    func fetchPartiesNear(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [PartyRecord] {
        // CloudKit doesn't support geo queries directly, so we fetch all active and filter
        let predicate = NSPredicate(format: "isActive == %@", NSNumber(value: true))
        let query = CKQuery(recordType: RecordType.party, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]

        let results = try await publicDatabase.records(matching: query, resultsLimit: 100)

        var parties: [PartyRecord] = []
        let userLocation = CLLocation(latitude: latitude, longitude: longitude)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                let partyLat = record["latitude"] as? Double ?? 0
                let partyLon = record["longitude"] as? Double ?? 0
                let partyLocation = CLLocation(latitude: partyLat, longitude: partyLon)

                let distanceKm = userLocation.distance(from: partyLocation) / 1000
                guard distanceKm <= radiusKm else { continue }

                let partyRecord = PartyRecord(
                    id: record.recordID.recordName,
                    name: record["name"] as? String ?? "",
                    hostUserId: record["hostUserId"] as? String ?? "",
                    hostDisplayName: record["hostDisplayName"] as? String ?? "",
                    description: record["description"] as? String,
                    latitude: partyLat,
                    longitude: partyLon,
                    locationName: record["locationName"] as? String,
                    isLocationHidden: record["isLocationHidden"] as? Bool ?? false,
                    startTime: record["startTime"] as? Date ?? Date(),
                    endTime: record["endTime"] as? Date,
                    maxAttendees: record["maxAttendees"] as? Int,
                    currentAttendeeCount: record["currentAttendeeCount"] as? Int ?? 0,
                    isActive: record["isActive"] as? Bool ?? true,
                    vibe: record["vibe"] as? String ?? "chill",
                    accessType: record["accessType"] as? String ?? "open"
                )
                parties.append(partyRecord)
            }
        }

        return parties
    }

    /// Update party in CloudKit
    func updateParty(_ party: Party) async throws {
        let recordID = CKRecord.ID(recordName: party.id.uuidString)

        let record: CKRecord
        do {
            record = try await publicDatabase.record(for: recordID)
        } catch {
            // Party doesn't exist in cloud yet
            _ = try await createParty(party)
            return
        }

        record["currentAttendeeCount"] = party.currentAttendeeCount
        record["isActive"] = party.isActive
        record["endTime"] = party.endTime

        try await publicDatabase.save(record)
    }

    /// Create attendee request in public database
    func createAttendeeRequest(partyId: String, attendee: PartyAttendee) async throws -> String {
        let recordID = CKRecord.ID(recordName: attendee.id.uuidString)
        let record = CKRecord(recordType: RecordType.partyAttendee, recordID: recordID)

        record["partyId"] = partyId
        record["userId"] = attendee.userId
        record["displayName"] = attendee.displayName
        record["emoji"] = attendee.emoji
        record["status"] = attendee.statusRawValue
        record["requestedAt"] = attendee.requestedAt
        record["profilePhotoAssetId"] = attendee.profilePhotoAssetId
        record["verificationStatus"] = attendee.verificationStatus
        record["followerCount"] = attendee.followerCount

        let savedRecord = try await publicDatabase.save(record)
        return savedRecord.recordID.recordName
    }

    /// Update attendee status
    func updateAttendeeStatus(attendeeId: String, status: String) async throws {
        let recordID = CKRecord.ID(recordName: attendeeId)
        let record = try await publicDatabase.record(for: recordID)

        record["status"] = status
        record["respondedAt"] = Date()

        try await publicDatabase.save(record)
    }

    /// Fetch attendees for a party
    func fetchPartyAttendees(partyId: String) async throws -> [AttendeeRecord] {
        let predicate = NSPredicate(format: "partyId == %@", partyId)
        let query = CKQuery(recordType: RecordType.partyAttendee, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "requestedAt", ascending: false)]

        let results = try await publicDatabase.records(matching: query)

        var attendees: [AttendeeRecord] = []

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                let attendeeRecord = AttendeeRecord(
                    id: record.recordID.recordName,
                    partyId: record["partyId"] as? String ?? "",
                    userId: record["userId"] as? String ?? "",
                    displayName: record["displayName"] as? String ?? "",
                    emoji: record["emoji"] as? String ?? "🎧",
                    status: record["status"] as? String ?? "requested",
                    requestedAt: record["requestedAt"] as? Date ?? Date(),
                    respondedAt: record["respondedAt"] as? Date,
                    verificationStatus: record["verificationStatus"] as? String,
                    followerCount: record["followerCount"] as? Int
                )
                attendees.append(attendeeRecord)
            }
        }

        return attendees
    }

    // MARK: - Subscriptions (Real-time updates)

    func subscribeToSquadUpdates(squadId: String, onChange: @escaping () -> Void) async throws {
        let predicate = NSPredicate(format: "squadId == %@", squadId)

        // Subscribe to location changes
        let locationSubscription = CKQuerySubscription(
            recordType: RecordType.location,
            predicate: predicate,
            subscriptionID: "location-\(squadId)",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )

        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        locationSubscription.notificationInfo = notification

        try await privateDatabase.save(locationSubscription)

        // Subscribe to message changes
        let messageSubscription = CKQuerySubscription(
            recordType: RecordType.message,
            predicate: predicate,
            subscriptionID: "message-\(squadId)",
            options: [.firesOnRecordCreation]
        )
        messageSubscription.notificationInfo = notification

        try await privateDatabase.save(messageSubscription)
    }
}

// MARK: - CloudKit Record Types for Party Discovery

struct PartyRecord {
    let id: String
    let name: String
    let hostUserId: String
    let hostDisplayName: String
    let description: String?
    let latitude: Double
    let longitude: Double
    let locationName: String?
    let isLocationHidden: Bool
    let startTime: Date
    let endTime: Date?
    let maxAttendees: Int?
    let currentAttendeeCount: Int
    let isActive: Bool
    let vibe: String
    let accessType: String
}

struct AttendeeRecord {
    let id: String
    let partyId: String
    let userId: String
    let displayName: String
    let emoji: String
    let status: String
    let requestedAt: Date
    let respondedAt: Date?
    let verificationStatus: String?
    let followerCount: Int?
}

// MARK: - Local-First Sync Engine
/// Uses CloudKit when available, works offline otherwise
final class LocalSyncEngine: ObservableObject {

    @Published private(set) var pendingUploads = 0
    @Published private(set) var lastSyncTime: Date?

    private let cloudKit = CloudKitService.shared
    private var pendingChanges: [PendingChange] = []

    struct PendingChange: Codable {
        let id: UUID
        let type: ChangeType
        let data: Data
        let createdAt: Date

        enum ChangeType: String, Codable {
            case location
            case message
            case squadJoin
            case squadLeave
        }
    }

    func queueLocationUpdate(squadId: String, userId: String, latitude: Double, longitude: Double, accuracy: Double) {
        // Try immediate upload if online
        Task {
            if cloudKit.isAvailable {
                try? await cloudKit.updateLocation(
                    squadId: squadId,
                    userId: userId,
                    latitude: latitude,
                    longitude: longitude,
                    accuracy: accuracy
                )
            } else {
                // Queue for later
                guard let encodedData = try? JSONEncoder().encode([
                    "squadId": squadId,
                    "userId": userId,
                    "latitude": String(latitude),
                    "longitude": String(longitude),
                    "accuracy": String(accuracy)
                ]) else {
                    print("[SyncEngine] Failed to encode location data")
                    return
                }
                let change = PendingChange(
                    id: UUID(),
                    type: .location,
                    data: encodedData,
                    createdAt: Date()
                )
                pendingChanges.append(change)
                await MainActor.run {
                    pendingUploads = pendingChanges.count
                }
            }
        }
    }

    func syncPendingChanges() async {
        guard cloudKit.isAvailable else { return }

        for change in pendingChanges {
            do {
                switch change.type {
                case .location:
                    if let data = try? JSONDecoder().decode([String: String].self, from: change.data) {
                        try await cloudKit.updateLocation(
                            squadId: data["squadId"] ?? "",
                            userId: data["userId"] ?? "",
                            latitude: Double(data["latitude"] ?? "0") ?? 0,
                            longitude: Double(data["longitude"] ?? "0") ?? 0,
                            accuracy: Double(data["accuracy"] ?? "0") ?? 0
                        )
                    }
                default:
                    break
                }
            } catch {
                print("[Sync] Failed to sync change: \(error)")
                continue
            }
        }

        pendingChanges.removeAll()
        await MainActor.run {
            pendingUploads = 0
            lastSyncTime = Date()
        }
    }
}
