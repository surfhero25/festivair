import Foundation

/// Represents a user's current status for squad communication
struct UserStatus: Codable, Equatable {
    let preset: StatusPreset?
    let customText: String?
    let setAt: Date
    let expiresAt: Date?

    var displayText: String {
        if let custom = customText, !custom.isEmpty {
            return custom
        }
        return preset?.displayText ?? ""
    }

    var emoji: String {
        preset?.emoji ?? ""
    }

    var isExpired: Bool {
        if let expires = expiresAt {
            return Date() > expires
        }
        return false
    }

    var isActive: Bool {
        !displayText.isEmpty && !isExpired
    }

    // MARK: - Factory Methods

    static func preset(_ preset: StatusPreset, expiresIn: TimeInterval? = 3600) -> UserStatus {
        UserStatus(
            preset: preset,
            customText: nil,
            setAt: Date(),
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) }
        )
    }

    static func custom(_ text: String, expiresIn: TimeInterval? = 3600) -> UserStatus {
        UserStatus(
            preset: nil,
            customText: text,
            setAt: Date(),
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) }
        )
    }

    static func cleared() -> UserStatus {
        UserStatus(preset: nil, customText: nil, setAt: Date(), expiresAt: nil)
    }
}

// MARK: - Status Presets
enum StatusPreset: String, Codable, CaseIterable {
    case headingToMainStage
    case atTheBar
    case needsWater
    case lookingForGroup
    case takingABreak
    case inLine
    case atMedical
    case headingOut
    case onTheWay
    case atMeetupSpot
    case gettingFood
    case atMerch
    case charging
    case bathroomBreak
    case lostInCrowd

    var displayText: String {
        switch self {
        case .headingToMainStage: return "Heading to Main Stage"
        case .atTheBar: return "At the bar"
        case .needsWater: return "Need water"
        case .lookingForGroup: return "Looking for group"
        case .takingABreak: return "Taking a break"
        case .inLine: return "In line"
        case .atMedical: return "At medical"
        case .headingOut: return "Heading out"
        case .onTheWay: return "On my way!"
        case .atMeetupSpot: return "At meetup spot"
        case .gettingFood: return "Getting food"
        case .atMerch: return "At merch"
        case .charging: return "Charging phone"
        case .bathroomBreak: return "Bathroom break"
        case .lostInCrowd: return "Lost in crowd"
        }
    }

    var emoji: String {
        switch self {
        case .headingToMainStage: return "🎵"
        case .atTheBar: return "🍺"
        case .needsWater: return "💧"
        case .lookingForGroup: return "👀"
        case .takingABreak: return "😴"
        case .inLine: return "🚶"
        case .atMedical: return "🏥"
        case .headingOut: return "👋"
        case .onTheWay: return "🏃"
        case .atMeetupSpot: return "📍"
        case .gettingFood: return "🍔"
        case .atMerch: return "👕"
        case .charging: return "🔋"
        case .bathroomBreak: return "🚻"
        case .lostInCrowd: return "🫣"
        }
    }

    /// Categorize presets for UI organization
    var category: StatusCategory {
        switch self {
        case .headingToMainStage, .onTheWay, .headingOut:
            return .moving
        case .atTheBar, .gettingFood, .atMerch:
            return .activity
        case .needsWater, .atMedical, .charging, .bathroomBreak:
            return .needs
        case .lookingForGroup, .atMeetupSpot, .lostInCrowd:
            return .squad
        case .takingABreak, .inLine:
            return .waiting
        }
    }
}

enum StatusCategory: String, CaseIterable {
    case moving = "Moving"
    case activity = "Activity"
    case needs = "Needs"
    case squad = "Squad"
    case waiting = "Waiting"

    var presets: [StatusPreset] {
        StatusPreset.allCases.filter { $0.category == self }
    }
}
