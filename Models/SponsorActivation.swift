import Foundation
import CoreLocation

/// A sponsor activation point on the festival map
struct SponsorActivation: Codable, Identifiable {
    let id: String
    var sponsorName: String
    var title: String
    var description: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double  // Geofence radius
    var iconUrl: String?
    var startTime: Date
    var endTime: Date
    var rewardType: RewardType?
    var rewardCode: String?
    var isActive: Bool

    // MARK: - Computed Properties

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isHappeningNow: Bool {
        let now = Date()
        return isActive && now >= startTime && now <= endTime
    }

    var hasEnded: Bool {
        Date() > endTime
    }

    var timeRemaining: TimeInterval {
        endTime.timeIntervalSince(Date())
    }

    var formattedTimeRange: String {
        "\(Formatters.time.string(from: startTime)) - \(Formatters.time.string(from: endTime))"
    }

    // MARK: - Distance Check

    func isUserInRange(userLatitude: Double, userLongitude: Double) -> Bool {
        let userLocation = CLLocation(latitude: userLatitude, longitude: userLongitude)
        let activationLocation = CLLocation(latitude: latitude, longitude: longitude)
        let distance = userLocation.distance(from: activationLocation)
        return distance <= radiusMeters
    }
}

// MARK: - Reward Type

enum RewardType: String, Codable, CaseIterable {
    case freebie = "freebie"        // Free item
    case discount = "discount"      // Discount code
    case merch = "merch"            // Merchandise
    case experience = "experience"  // VIP experience
    case points = "points"          // Loyalty points

    var displayName: String {
        switch self {
        case .freebie: return "Free Item"
        case .discount: return "Discount"
        case .merch: return "Merch"
        case .experience: return "Experience"
        case .points: return "Points"
        }
    }

    var icon: String {
        switch self {
        case .freebie: return "gift.fill"
        case .discount: return "percent"
        case .merch: return "tshirt.fill"
        case .experience: return "star.fill"
        case .points: return "bitcoinsign.circle.fill"
        }
    }
}

// MARK: - Sample Data

extension SponsorActivation {
    static var samples: [SponsorActivation] {
        [
            SponsorActivation(
                id: "1",
                sponsorName: "Red Bull",
                title: "Energy Station",
                description: "Get a free Red Bull at the Energy Station!",
                latitude: Constants.DefaultLocation.latitude,
                longitude: Constants.DefaultLocation.longitude,
                radiusMeters: 50,
                iconUrl: nil,
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600 * 8),
                rewardType: .freebie,
                rewardCode: "REDBULL2026",
                isActive: true
            ),
            SponsorActivation(
                id: "2",
                sponsorName: "Spotify",
                title: "Listening Lounge",
                description: "Scan for 3 months free Spotify Premium",
                latitude: Constants.DefaultLocation.latitude + 0.0008,
                longitude: Constants.DefaultLocation.longitude - 0.0008,
                radiusMeters: 30,
                iconUrl: nil,
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600 * 8),
                rewardType: .discount,
                rewardCode: "FEST3FREE",
                isActive: true
            )
        ]
    }
}
