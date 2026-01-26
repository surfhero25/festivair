import Foundation
import CoreLocation

/// A meetup pin dropped by a squad member to indicate a meeting point
struct MeetupPin: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let name: String
    let creatorId: String
    let creatorName: String
    let createdAt: Date
    let expiresAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isActive: Bool {
        !isExpired
    }

    var timeRemaining: String {
        let remaining = expiresAt.timeIntervalSince(Date())

        if remaining <= 0 {
            return "Expired"
        } else if remaining < 60 {
            return "< 1 min"
        } else if remaining < 3600 {
            let minutes = Int(remaining / 60)
            return "\(minutes) min left"
        } else {
            let hours = Int(remaining / 3600)
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "\(hours)h \(minutes)m left"
            }
            return "\(hours)h left"
        }
    }

    // MARK: - Factory Methods

    static func create(
        at coordinate: CLLocationCoordinate2D,
        name: String,
        creatorId: String,
        creatorName: String,
        expiresIn: TimeInterval = 1800 // 30 minutes default
    ) -> MeetupPin {
        MeetupPin(
            id: UUID(),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: name,
            creatorId: creatorId,
            creatorName: creatorName,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    // MARK: - Conversion to/from Payload

    func toPayload() -> MeshMessagePayload.MeetupPinPayload {
        MeshMessagePayload.MeetupPinPayload(
            id: id,
            latitude: latitude,
            longitude: longitude,
            name: name,
            creatorId: creatorId,
            creatorName: creatorName,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }

    init(from payload: MeshMessagePayload.MeetupPinPayload) {
        self.id = payload.id
        self.latitude = payload.latitude
        self.longitude = payload.longitude
        self.name = payload.name
        self.creatorId = payload.creatorId
        self.creatorName = payload.creatorName
        self.createdAt = payload.createdAt
        self.expiresAt = payload.expiresAt
    }

    init(
        id: UUID,
        latitude: Double,
        longitude: Double,
        name: String,
        creatorId: String,
        creatorName: String,
        createdAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.creatorId = creatorId
        self.creatorName = creatorName
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

// MARK: - Preset Pin Names
enum MeetupPinPreset: String, CaseIterable {
    case meetHere = "Meet me here!"
    case meetingSpot = "Meeting spot"
    case groupUp = "Group up here"
    case foundIt = "Found it!"
    case thisWay = "This way"
    case stage = "At this stage"
    case food = "Food spot"
    case drinks = "Drinks here"
    case bathroom = "Bathroom nearby"
    case chill = "Chill zone"

    var emoji: String {
        switch self {
        case .meetHere: return "📍"
        case .meetingSpot: return "🎯"
        case .groupUp: return "👥"
        case .foundIt: return "✨"
        case .thisWay: return "👉"
        case .stage: return "🎵"
        case .food: return "🍔"
        case .drinks: return "🍺"
        case .bathroom: return "🚻"
        case .chill: return "😎"
        }
    }
}
