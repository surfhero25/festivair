import Foundation

enum Constants {

    // MARK: - App Info
    static let appName = "FestivAir"
    static let appVersion = "1.0.0"
    static let appBundleId = "com.festivair.app"

    // MARK: - Mesh Networking
    enum Mesh {
        static let serviceType = "festivair-mesh"
        static let maxPeers = 12
        static let messageTTL = 3
        static let heartbeatInterval: TimeInterval = 30
        static let seenMessageCacheSize = 1000
    }

    // MARK: - Location
    enum Location {
        static let activeUpdateInterval: TimeInterval = 30
        static let backgroundUpdateInterval: TimeInterval = 120
        static let lowPowerUpdateInterval: TimeInterval = 300
        static let stationaryUpdateInterval: TimeInterval = 600
        static let findMeDuration: TimeInterval = 60
    }

    // MARK: - Gateway
    enum Gateway {
        static let electionInterval: TimeInterval = 30
        static let minBatteryLevel = 20
        static let rotationBatteryLevel = 30
        static let gatewayRotationInterval: TimeInterval = 900 // 15 minutes
    }

    // MARK: - Sync
    enum Sync {
        static let maxPendingChanges = 100
        static let syncRetryInterval: TimeInterval = 60
        static let offlineQueueKey = "FestivAir.OfflineQueue"
    }

    // MARK: - Notifications
    enum Notifications {
        static let defaultLeadTime: TimeInterval = 600 // 10 minutes
        static let setTimeCategoryId = "SET_TIME_REMINDER"
        static let memberOfflineCategoryId = "MEMBER_OFFLINE"
    }

    // MARK: - User Defaults Keys
    enum UserDefaultsKeys {
        static let onboarded = "FestivAir.Onboarded"
        static let userId = "FestivAir.UserId"
        static let displayName = "FestivAir.DisplayName"
        static let emoji = "FestivAir.Emoji"
        static let currentSquadId = "FestivAir.CurrentSquadId"
        static let currentCloudSquadId = "FestivAir.CurrentCloudSquadId"
        static let currentJoinCode = "FestivAir.CurrentJoinCode"  // Squad join code for mesh filtering
        static let lowPowerMode = "FestivAir.LowPowerMode"
        static let notifyBefore = "FestivAir.NotifyBefore"
        static let ageConfirmed = "FestivAir.AgeConfirmed"  // User confirmed they are 18+
    }

    // MARK: - Firebase Collections
    enum Firebase {
        static let usersCollection = "users"
        static let squadsCollection = "squads"
        static let eventsCollection = "events"
        static let locationsSubcollection = "locations"
        static let messagesSubcollection = "messages"
    }

    // MARK: - URL Schemes
    enum URLSchemes {
        static let appScheme = "festivair"
        static let squadJoinPath = "squad"
        // festivair://squad/ABC123

        static func squadJoinURL(code: String) -> URL? {
            URL(string: "\(appScheme)://\(squadJoinPath)/\(code)")
        }
    }

    // MARK: - Squad Limits
    enum Squad {
        static let maxMembers = 50
        static let codeLength = 8  // Changed from 6
        static let codeCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // No O, 0, I, 1
        static let freeMemberLimit = 4
        static let festivalPassMemberLimit = 8
        static let crewPassMemberLimit = 20
        static let seasonPassMemberLimit = 20
        static let joinAttemptRateLimit = 3          // per minute
        static let joinAttemptRateWindow: TimeInterval = 60
    }

    // MARK: - Mesh Relay
    enum MeshRelay {
        static let maxHops = 10                    // Maximum relay hops before dropping
        static let packetTTL: TimeInterval = 300  // 5 min - packets expire
        static let maxRelaysPerMinute = 500       // Rate limit per device
        static let locationBroadcastInterval: TimeInterval = 30  // GPS update frequency via relay
        static let gatewaySyncInterval: TimeInterval = 10        // Cloud sync when gateway
    }

    // MARK: - Protocol V2

    enum ProtocolV2 {
        static let version: Int = 2
        static let presencePulseInterval: TimeInterval = 300       // 5 minutes
        static let ambientResponseInterval: TimeInterval = 60      // 1 minute
        static let ambientResponseReducedInterval: TimeInterval = 90 // 1.5 min (battery 30-50%)
        static let preciseResponseInterval: TimeInterval = 3       // 3 seconds
        static let requestRenewalInterval: TimeInterval = 60       // 1 minute
        static let sessionTimeout: TimeInterval = 90               // drop state after no renewal
        static let stalePinMaxAge: TimeInterval = 3600             // 1 hour — hide pins older than this
        static let stalePinFadeAge: TimeInterval = 300             // 5 min — start fading
        static let chatFallbackDelay: TimeInterval = 30            // send standalone if no mesh activity
        static let urgentChatRateLimit: Int = 5                    // max per 10 minutes
        static let urgentChatRateWindow: TimeInterval = 600        // 10 minutes
        static let sosUpdateInterval: TimeInterval = 3             // SOS broadcasts every 3s
    }

    // MARK: - Payload Budgets (bytes)

    enum PayloadBudget {
        static let presencePulse: Int = 100
        static let locationRequest: Int = 50
        static let locationResponse: Int = 200
        static let preciseLocationRequest: Int = 80
        static let preciseLocationResponse: Int = 150
        static let urgentChat: Int = 500
        static let chat: Int = 500
        static let squadAnnouncement: Int = 1000
        static let sos: Int = 150
        static let stopPreciseLocation: Int = 50
        static let requestRenewal: Int = 80
        static let clusterHandoff: Int = 200
    }

    // MARK: - Battery Tiers

    enum BatteryTier {
        static let fullMin: Float = 0.50
        static let reducedMin: Float = 0.30
        static let passiveMin: Float = 0.15

        static func tier(for level: Float) -> Tier {
            switch level {
            case fullMin...1.0: return .full
            case reducedMin..<fullMin: return .reduced
            case passiveMin..<reducedMin: return .passive
            default: return .survival
            }
        }

        enum Tier: String, Codable {
            case full, reduced, passive, survival
        }
    }

    // MARK: - Profile Settings
    enum Profile {
        static let maxBioLength = 280
        static let maxGalleryPhotos = 6          // Premium only
        static let profilePhotoMaxSizeBytes = 2_000_000   // 2MB
        static let galleryPhotoMaxSizeBytes = 1_000_000   // 1MB
        static let profilePhotoMaxDimension = 1024        // pixels
        static let thumbnailDimension = 200               // pixels
    }

    // MARK: - Verification Thresholds
    enum Verification {
        static let influencerFollowers = 10_000
        static let creatorFollowers = 50_000
        static let vipFollowers = 100_000
    }

    // MARK: - Subscription Product IDs
    enum Subscriptions {
        static let festivalPass = "com.festivair.festivalpass"
        static let crewPass = "com.festivair.crewpass"
        static let seasonPass = "com.festivair.seasonpass"

        static let festivalPassPrice = "$2.99"
        static let crewPassPrice = "$6.99"
        static let seasonPassPrice = "$14.99"
    }

    // MARK: - Parties
    enum Party {
        static let maxAttendeesDefault = 50
        static let discoveryRadiusKm = 10.0
        static let vibeOptions = ["chill", "hype", "underground", "rooftop", "afterHours", "pool", "vip"]
    }

    // MARK: - Default Location (Los Angeles)
    enum DefaultLocation {
        static let latitude = 34.0522
        static let longitude = -118.2437
        static let name = "Los Angeles, CA"
    }

    // MARK: - Peer Tracking
    enum PeerTracking {
        static let offlineThreshold: TimeInterval = 120  // 2 minutes
        static let removeThreshold: TimeInterval = 3600  // 1 hour
        static let staleThreshold: TimeInterval = 120    // 2 minutes
    }

    // MARK: - Sponsor Activations
    enum Sponsor {
        static let nearbyRadiusMeters: Double = 500
    }

    // MARK: - Image Cache
    enum ImageCache {
        static let memoryCacheLimitBytes = 50 * 1024 * 1024  // 50MB
    }
}
