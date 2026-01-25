import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var avatarEmoji: String
    var lastSeen: Date
    var batteryLevel: Int?
    var hasService: Bool

    // Location stored separately for frequent updates
    var latitude: Double?
    var longitude: Double?
    var locationAccuracy: Double?
    var locationTimestamp: Date?
    var locationSource: String? // "gps", "mesh", "gateway"

    // Firebase sync
    var fcmToken: String?
    var firebaseId: String?

    // MARK: - Profile
    var bio: String?
    var profilePhotoAssetId: String?  // CloudKit asset ID
    var galleryPhotoIds: [String]?    // Premium feature - up to 6 photos

    // MARK: - Social Links
    var instagramHandle: String?
    var instagramFollowers: Int?
    var tiktokHandle: String?
    var tiktokFollowers: Int?

    // MARK: - Verification & Badges
    var verificationStatus: String?  // VerificationStatus raw value
    var badges: [String]?            // UserBadge raw values

    // MARK: - Subscription
    var premiumTier: String?         // PremiumTier raw value
    var premiumExpiresAt: Date?

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \SquadMembership.user)
    var memberships: [SquadMembership]?

    init(
        id: UUID = UUID(),
        displayName: String,
        avatarEmoji: String = "🎧",
        lastSeen: Date = Date(),
        batteryLevel: Int? = nil,
        hasService: Bool = true,
        bio: String? = nil,
        premiumTier: PremiumTier = .free
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.lastSeen = lastSeen
        self.batteryLevel = batteryLevel
        self.hasService = hasService
        self.bio = bio
        self.premiumTier = premiumTier.rawValue
        self.verificationStatus = VerificationStatus.none.rawValue
        self.badges = []
    }

    // MARK: - Computed Properties

    var verification: VerificationStatus {
        get { VerificationStatus(rawValue: verificationStatus ?? "") ?? .none }
        set { verificationStatus = newValue.rawValue }
    }

    var tier: PremiumTier {
        get { PremiumTier(rawValue: premiumTier ?? "") ?? .free }
        set { premiumTier = newValue.rawValue }
    }

    var userBadges: [UserBadge] {
        get { (badges ?? []).compactMap { UserBadge(rawValue: $0) } }
        set { badges = newValue.map { $0.rawValue } }
    }

    var isVerified: Bool {
        verification != .none
    }

    var isPremium: Bool {
        tier != .free && (premiumExpiresAt == nil || premiumExpiresAt! > Date())
    }

    var canUploadGallery: Bool {
        tier != .free
    }

    var canHostExclusiveParties: Bool {
        tier == .vip
    }

    var squadLimit: Int {
        switch tier {
        case .free: return 4
        case .basic: return 8
        case .vip: return 12
        }
    }

    // MARK: - Social Helpers

    var instagramURL: URL? {
        guard let handle = instagramHandle, !handle.isEmpty else { return nil }
        return URL(string: "https://instagram.com/\(handle)")
    }

    var tiktokURL: URL? {
        guard let handle = tiktokHandle, !handle.isEmpty else { return nil }
        return URL(string: "https://tiktok.com/@\(handle)")
    }

    var totalFollowers: Int {
        (instagramFollowers ?? 0) + (tiktokFollowers ?? 0)
    }

    /// Auto-determine verification based on follower count
    func updateVerificationFromFollowers() {
        let followers = max(instagramFollowers ?? 0, tiktokFollowers ?? 0)
        if followers >= 100_000 {
            verification = .vip
        } else if followers >= 50_000 {
            verification = .creator
        } else if followers >= 10_000 {
            verification = .influencer
        }
        // Note: Don't downgrade if manually set to .artist or other status
    }

    var location: Location? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return Location(
            latitude: lat,
            longitude: lon,
            accuracy: locationAccuracy ?? 0,
            timestamp: locationTimestamp ?? Date(),
            source: LocationSource(rawValue: locationSource ?? "gps") ?? .gps
        )
    }

    func updateLocation(_ location: Location) {
        self.latitude = location.latitude
        self.longitude = location.longitude
        self.locationAccuracy = location.accuracy
        self.locationTimestamp = location.timestamp
        self.locationSource = location.source.rawValue
        self.lastSeen = Date()
    }
}

// MARK: - Location Value Type
struct Location: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var timestamp: Date
    var source: LocationSource

    var coordinate: (latitude: Double, longitude: Double) {
        (latitude, longitude)
    }
}

enum LocationSource: String, Codable {
    case gps = "gps"
    case mesh = "mesh"
    case gateway = "gateway"
}

// MARK: - Verification Status

enum VerificationStatus: String, Codable, CaseIterable {
    case none = "none"
    case influencer = "influencer"  // 10k+ followers
    case creator = "creator"        // 50k+ followers
    case vip = "vip"                // 100k+ followers OR VIP subscription
    case artist = "artist"          // Manually verified artist/performer

    var displayName: String {
        switch self {
        case .none: return ""
        case .influencer: return "Influencer"
        case .creator: return "Creator"
        case .vip: return "VIP"
        case .artist: return "Artist"
        }
    }

    var badgeIcon: String {
        switch self {
        case .none: return ""
        case .influencer: return "checkmark.seal.fill"
        case .creator: return "star.fill"
        case .vip: return "crown.fill"
        case .artist: return "music.mic"
        }
    }
}

// MARK: - User Badges

enum UserBadge: String, Codable, CaseIterable {
    case earlyAdopter = "earlyAdopter"
    case squadLeader = "squadLeader"      // Created 3+ squads
    case partyHost = "partyHost"          // Hosted 3+ parties
    case festivalVet = "festivalVet"      // Used app at 5+ events
    case nightOwl = "nightOwl"            // Active after 2am
    case connector = "connector"          // Invited 10+ people

    var displayName: String {
        switch self {
        case .earlyAdopter: return "Early Adopter"
        case .squadLeader: return "Squad Leader"
        case .partyHost: return "Party Host"
        case .festivalVet: return "Festival Vet"
        case .nightOwl: return "Night Owl"
        case .connector: return "Connector"
        }
    }

    var icon: String {
        switch self {
        case .earlyAdopter: return "star.circle.fill"
        case .squadLeader: return "person.3.fill"
        case .partyHost: return "party.popper.fill"
        case .festivalVet: return "ticket.fill"
        case .nightOwl: return "moon.stars.fill"
        case .connector: return "link.circle.fill"
        }
    }
}

// MARK: - Premium Tier

enum PremiumTier: String, Codable, CaseIterable {
    case free = "free"
    case basic = "basic"    // $4.99/month
    case vip = "vip"        // $14.99/month

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .basic: return "Basic"
        case .vip: return "VIP"
        }
    }

    var squadLimit: Int {
        switch self {
        case .free: return 4
        case .basic: return 8
        case .vip: return 12
        }
    }

    var monthlyPrice: String {
        switch self {
        case .free: return "Free"
        case .basic: return "$4.99/mo"
        case .vip: return "$14.99/mo"
        }
    }
}
