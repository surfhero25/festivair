import Foundation
import ActivityKit

/// Defines the Live Activity for FestivAir navigation and SOS.
struct FestivAirActivityAttributes: ActivityAttributes {

    /// Static data that doesn't change during the activity
    struct ContentState: Codable, Hashable {
        // Navigation state
        var mode: ActivityMode
        var targetName: String
        var distanceMeters: Double?
        var bearingDegrees: Double?   // compass direction to target
        var isArrived: Bool

        // SOS state
        var isSOSActive: Bool
        var sosMemberName: String?

        enum ActivityMode: String, Codable, Hashable {
            case ambient     // "Squad connected" — subtle
            case navigate    // Arrow + distance
            case sos         // Red alert
            case idle        // Should not have a Live Activity
        }

        /// Direction arrow character based on bearing
        var directionArrow: String {
            guard let bearing = bearingDegrees else { return "•" }
            let normalized = ((bearing.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            switch normalized {
            case 337.5..<360, 0..<22.5: return "↑"
            case 22.5..<67.5: return "↗"
            case 67.5..<112.5: return "→"
            case 112.5..<157.5: return "↘"
            case 157.5..<202.5: return "↓"
            case 202.5..<247.5: return "↙"
            case 247.5..<292.5: return "←"
            case 292.5..<337.5: return "↖"
            default: return "•"
            }
        }

        /// Formatted distance string
        var distanceText: String {
            guard let distance = distanceMeters else { return "" }
            if isArrived { return "Arrived" }
            if distance < 10 { return "Right here" }
            if distance < 1000 { return "\(Int(distance))m" }
            return String(format: "%.1fkm", distance / 1000)
        }
    }

    // Static attributes (set once when activity starts)
    var squadName: String
}
