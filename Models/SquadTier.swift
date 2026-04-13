import Foundation

/// Squad premium tier — stored on the squad record in CloudKit, not on any device.
enum SquadTier: String, Codable, CaseIterable {
    case free
    case festivalPass
    case crewPass
    case seasonPass

    /// Maximum squad members for this tier
    var memberLimit: Int {
        switch self {
        case .free: return Constants.Squad.freeMemberLimit
        case .festivalPass: return Constants.Squad.festivalPassMemberLimit
        case .crewPass: return Constants.Squad.crewPassMemberLimit
        case .seasonPass: return Constants.Squad.seasonPassMemberLimit
        }
    }

    /// Display name
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .festivalPass: return "Festival Pass"
        case .crewPass: return "Crew Pass"
        case .seasonPass: return "Season Pass"
        }
    }

    /// Price text
    var priceText: String {
        switch self {
        case .free: return "Free"
        case .festivalPass: return Constants.Subscriptions.festivalPassPrice
        case .crewPass: return Constants.Subscriptions.crewPassPrice
        case .seasonPass: return "\(Constants.Subscriptions.seasonPassPrice)/yr"
        }
    }

    /// Whether this tier includes squad announcements
    var hasAnnouncements: Bool {
        self != .free
    }

    /// Whether this tier includes offline venue maps
    var hasOfflineMaps: Bool {
        self != .free
    }

    /// Whether this tier includes set time alerts
    var hasSetTimeAlerts: Bool {
        self != .free
    }

    /// Whether this tier includes custom squad themes
    var hasCustomThemes: Bool {
        self == .crewPass || self == .seasonPass
    }

    /// Whether this tier includes after party pins
    var hasAfterPartyPins: Bool {
        self == .crewPass || self == .seasonPass
    }

    /// Whether this tier includes festival history
    var hasFestivalHistory: Bool {
        self == .seasonPass
    }

    /// StoreKit product ID for purchasing this tier
    var productId: String? {
        switch self {
        case .free: return nil
        case .festivalPass: return Constants.Subscriptions.festivalPass
        case .crewPass: return Constants.Subscriptions.crewPass
        case .seasonPass: return Constants.Subscriptions.seasonPass
        }
    }

    /// Initialize from CloudKit record value
    init(rawCloudKitValue: String?) {
        guard let value = rawCloudKitValue,
              let tier = SquadTier(rawValue: value) else {
            self = .free
            return
        }
        self = tier
    }
}

/// Represents the premium state of a squad — loaded from CloudKit
struct SquadPremiumState {
    let tier: SquadTier
    let expiresAt: Date?
    let purchasedBy: String?  // userId of purchaser

    /// Whether the tier is currently active (not expired)
    var isActive: Bool {
        guard tier != .free else { return true }  // Free never expires
        guard let expires = expiresAt else { return false }
        return expires > Date()
    }

    /// The effective tier (falls back to free if expired)
    var effectiveTier: SquadTier {
        isActive ? tier : .free
    }

    /// Whether a new member can join this squad
    func canAddMember(currentCount: Int) -> Bool {
        currentCount < effectiveTier.memberLimit
    }

    /// Static free state
    static let free = SquadPremiumState(tier: .free, expiresAt: nil, purchasedBy: nil)
}
