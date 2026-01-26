import Foundation
import SwiftData

/// Represents a user's attendance or request to attend a party
@Model
final class PartyAttendee {
    @Attribute(.unique) var id: UUID
    var partyId: UUID
    var userId: String
    var displayName: String
    var emoji: String

    // Status
    var statusRawValue: String
    var requestedAt: Date
    var respondedAt: Date?

    // Profile info for host review
    var profilePhotoAssetId: String?
    var verificationStatus: String?
    var followerCount: Int?

    // CloudKit sync
    var cloudKitRecordId: String?

    // Relationship
    var party: Party?

    init(
        id: UUID = UUID(),
        partyId: UUID,
        userId: String,
        displayName: String,
        emoji: String = "🎧",
        status: AttendeeStatus = .requested,
        profilePhotoAssetId: String? = nil,
        verificationStatus: String? = nil,
        followerCount: Int? = nil
    ) {
        self.id = id
        self.partyId = partyId
        self.userId = userId
        self.displayName = displayName
        self.emoji = emoji
        self.statusRawValue = status.rawValue
        self.requestedAt = Date()
        self.profilePhotoAssetId = profilePhotoAssetId
        self.verificationStatus = verificationStatus
        self.followerCount = followerCount
    }

    // MARK: - Computed Properties

    var status: AttendeeStatus {
        get { AttendeeStatus(rawValue: statusRawValue) ?? .requested }
        set { statusRawValue = newValue.rawValue }
    }

    var isApproved: Bool {
        status == .approved || status == .attending
    }

    var isPending: Bool {
        status == .requested
    }

    var verification: VerificationStatus? {
        guard let raw = verificationStatus else { return nil }
        return VerificationStatus(rawValue: raw)
    }

    var formattedFollowers: String? {
        guard let count = followerCount, count > 0 else { return nil }

        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Attendee Status

enum AttendeeStatus: String, Codable, CaseIterable {
    case requested = "requested"   // Waiting for host approval
    case approved = "approved"     // Approved but not confirmed going
    case declined = "declined"     // Host declined
    case attending = "attending"   // Confirmed attending
    case left = "left"             // Left the party

    var displayName: String {
        switch self {
        case .requested: return "Pending"
        case .approved: return "Approved"
        case .declined: return "Declined"
        case .attending: return "Attending"
        case .left: return "Left"
        }
    }

    var icon: String {
        switch self {
        case .requested: return "clock.fill"
        case .approved: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .attending: return "person.fill.checkmark"
        case .left: return "arrow.right.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .requested: return "orange"
        case .approved: return "green"
        case .declined: return "red"
        case .attending: return "purple"
        case .left: return "gray"
        }
    }
}

// MARK: - Convenience Init from User

extension PartyAttendee {
    convenience init(partyId: UUID, user: User) {
        self.init(
            partyId: partyId,
            userId: user.id.uuidString,
            displayName: user.displayName,
            emoji: user.avatarEmoji,
            status: .requested,
            profilePhotoAssetId: user.profilePhotoAssetId,
            verificationStatus: user.verificationStatus,
            followerCount: user.totalFollowers
        )
    }
}
