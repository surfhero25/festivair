import Foundation
import SwiftData

/// A party or gathering that users can create and join
@Model
final class Party {
    @Attribute(.unique) var id: UUID
    var name: String
    var hostUserId: String
    var hostDisplayName: String
    var partyDescription: String?

    // Location
    var latitude: Double
    var longitude: Double
    var locationName: String?
    var isLocationHidden: Bool  // True until approved for exclusive parties

    // Timing
    var startTime: Date
    var endTime: Date?

    // Capacity
    var maxAttendees: Int?
    var currentAttendeeCount: Int

    // Status
    var isActive: Bool
    var createdAt: Date

    // Type & Vibe
    var vibeRawValue: String
    var accessTypeRawValue: String

    // CloudKit sync
    var cloudKitRecordId: String?

    init(
        id: UUID = UUID(),
        name: String,
        hostUserId: String,
        hostDisplayName: String,
        description: String? = nil,
        latitude: Double,
        longitude: Double,
        locationName: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        maxAttendees: Int? = nil,
        vibe: PartyVibe = .chill,
        accessType: PartyAccessType = .open
    ) {
        self.id = id
        self.name = name
        self.hostUserId = hostUserId
        self.hostDisplayName = hostDisplayName
        self.partyDescription = description
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.isLocationHidden = accessType != .open
        self.startTime = startTime
        self.endTime = endTime
        self.maxAttendees = maxAttendees
        self.currentAttendeeCount = 0
        self.isActive = true
        self.createdAt = Date()
        self.vibeRawValue = vibe.rawValue
        self.accessTypeRawValue = accessType.rawValue
    }

    // MARK: - Computed Properties

    var vibe: PartyVibe {
        get { PartyVibe(rawValue: vibeRawValue) ?? .chill }
        set { vibeRawValue = newValue.rawValue }
    }

    var accessType: PartyAccessType {
        get { PartyAccessType(rawValue: accessTypeRawValue) ?? .open }
        set { accessTypeRawValue = newValue.rawValue }
    }

    var isExclusive: Bool {
        accessType != .open
    }

    var isFull: Bool {
        guard let max = maxAttendees else { return false }
        return currentAttendeeCount >= max
    }

    var spotsRemaining: Int? {
        guard let maxAtt = maxAttendees else { return nil }
        return Swift.max(0, maxAtt - currentAttendeeCount)
    }

    var isHappeningNow: Bool {
        let now = Date()
        if let end = endTime {
            return now >= startTime && now <= end
        }
        return now >= startTime
    }

    var hasEnded: Bool {
        guard let end = endTime else { return false }
        return Date() > end
    }

    var timeUntilStart: TimeInterval {
        startTime.timeIntervalSince(Date())
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var result = formatter.string(from: startTime)
        if let end = endTime {
            result += " - " + formatter.string(from: end)
        }
        return result
    }
}

// MARK: - Party Vibe

enum PartyVibe: String, Codable, CaseIterable {
    case chill = "chill"
    case hype = "hype"
    case underground = "underground"
    case rooftop = "rooftop"
    case afterHours = "afterHours"
    case pool = "pool"
    case vip = "vip"

    var displayName: String {
        switch self {
        case .chill: return "Chill"
        case .hype: return "Hype"
        case .underground: return "Underground"
        case .rooftop: return "Rooftop"
        case .afterHours: return "After Hours"
        case .pool: return "Pool Party"
        case .vip: return "VIP"
        }
    }

    var emoji: String {
        switch self {
        case .chill: return "🌴"
        case .hype: return "🔥"
        case .underground: return "🎧"
        case .rooftop: return "🌆"
        case .afterHours: return "🌙"
        case .pool: return "🏊"
        case .vip: return "👑"
        }
    }

    var color: String {
        switch self {
        case .chill: return "green"
        case .hype: return "orange"
        case .underground: return "purple"
        case .rooftop: return "blue"
        case .afterHours: return "indigo"
        case .pool: return "cyan"
        case .vip: return "yellow"
        }
    }
}

// MARK: - Party Access Type

enum PartyAccessType: String, Codable, CaseIterable {
    case open = "open"              // Anyone can join
    case approval = "approval"      // Host must approve (VIP only)
    case inviteOnly = "inviteOnly"  // Invite only (VIP only)

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .approval: return "Approval Required"
        case .inviteOnly: return "Invite Only"
        }
    }

    var icon: String {
        switch self {
        case .open: return "door.left.hand.open"
        case .approval: return "hand.raised.fill"
        case .inviteOnly: return "envelope.fill"
        }
    }

    var requiresVIP: Bool {
        self != .open
    }
}
