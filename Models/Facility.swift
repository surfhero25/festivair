import Foundation
import CoreLocation
import SwiftUI

/// Represents a facility location at a festival venue
struct Facility: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: FacilityType
    let latitude: Double
    let longitude: Double
    let description: String?
    let isOpen: Bool
    let openTime: Date?
    let closeTime: Date?
    let venueId: UUID

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Check if facility is currently open (if hours are specified)
    var isCurrentlyOpen: Bool {
        guard let open = openTime, let close = closeTime else {
            return isOpen
        }

        let now = Date()
        let calendar = Calendar.current
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
        let openComponents = calendar.dateComponents([.hour, .minute], from: open)
        let closeComponents = calendar.dateComponents([.hour, .minute], from: close)

        guard let nowMinutes = nowComponents.hour.map({ $0 * 60 + (nowComponents.minute ?? 0) }),
              let openMinutes = openComponents.hour.map({ $0 * 60 + (openComponents.minute ?? 0) }),
              let closeMinutes = closeComponents.hour.map({ $0 * 60 + (closeComponents.minute ?? 0) }) else {
            return isOpen
        }

        // Handle overnight hours (e.g., 10pm - 4am)
        if closeMinutes < openMinutes {
            return nowMinutes >= openMinutes || nowMinutes <= closeMinutes
        }

        return nowMinutes >= openMinutes && nowMinutes <= closeMinutes
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: FacilityType,
        latitude: Double,
        longitude: Double,
        description: String? = nil,
        isOpen: Bool = true,
        openTime: Date? = nil,
        closeTime: Date? = nil,
        venueId: UUID
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.latitude = latitude
        self.longitude = longitude
        self.description = description
        self.isOpen = isOpen
        self.openTime = openTime
        self.closeTime = closeTime
        self.venueId = venueId
    }
}

// MARK: - Facility Type
enum FacilityType: String, Codable, CaseIterable {
    case water
    case bathroom
    case medical
    case food
    case bar
    case merchandise
    case charging
    case atm
    case entrance
    case exit
    case rideshare
    case lostAndFound
    case info
    case stage

    var displayName: String {
        switch self {
        case .water: return "Water Station"
        case .bathroom: return "Restroom"
        case .medical: return "Medical/First Aid"
        case .food: return "Food Vendor"
        case .bar: return "Bar"
        case .merchandise: return "Merch"
        case .charging: return "Charging Station"
        case .atm: return "ATM"
        case .entrance: return "Entrance"
        case .exit: return "Exit"
        case .rideshare: return "Rideshare Pickup"
        case .lostAndFound: return "Lost & Found"
        case .info: return "Information"
        case .stage: return "Stage"
        }
    }

    var emoji: String {
        switch self {
        case .water: return "💧"
        case .bathroom: return "🚻"
        case .medical: return "🏥"
        case .food: return "🍔"
        case .bar: return "🍺"
        case .merchandise: return "👕"
        case .charging: return "🔋"
        case .atm: return "💵"
        case .entrance: return "🚪"
        case .exit: return "🚪"
        case .rideshare: return "🚗"
        case .lostAndFound: return "📦"
        case .info: return "ℹ️"
        case .stage: return "🎵"
        }
    }

    var icon: String {
        switch self {
        case .water: return "drop.fill"
        case .bathroom: return "figure.stand.dress.line.vertical.figure"
        case .medical: return "cross.fill"
        case .food: return "fork.knife"
        case .bar: return "wineglass.fill"
        case .merchandise: return "tshirt.fill"
        case .charging: return "battery.100.bolt"
        case .atm: return "dollarsign.circle.fill"
        case .entrance: return "arrow.right.to.line"
        case .exit: return "arrow.left.to.line"
        case .rideshare: return "car.fill"
        case .lostAndFound: return "shippingbox.fill"
        case .info: return "info.circle.fill"
        case .stage: return "music.note.house.fill"
        }
    }

    var color: Color {
        switch self {
        case .water: return .blue
        case .bathroom: return .cyan
        case .medical: return .red
        case .food: return .orange
        case .bar: return .yellow
        case .merchandise: return .purple
        case .charging: return .green
        case .atm: return .green
        case .entrance: return .teal
        case .exit: return .teal
        case .rideshare: return .indigo
        case .lostAndFound: return .brown
        case .info: return .blue
        case .stage: return .pink
        }
    }

    /// Priority for "nearest" searches (lower = more essential)
    var priority: Int {
        switch self {
        case .medical: return 1
        case .water: return 2
        case .bathroom: return 3
        case .exit: return 4
        case .charging: return 5
        case .food: return 6
        case .bar: return 7
        case .atm: return 8
        case .info: return 9
        case .entrance: return 10
        case .rideshare: return 11
        case .merchandise: return 12
        case .lostAndFound: return 13
        case .stage: return 14
        }
    }

    /// Common quick-access facility types
    static var quickAccess: [FacilityType] {
        [.water, .bathroom, .medical, .food, .charging]
    }
}
