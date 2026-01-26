import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#endif

// MARK: - Cached Formatters
enum Formatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static let timeShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    static let dayOfWeek: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    static let dayShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    /// Returns a formatter for custom format (cached per format string)
    private static var customFormatters: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    static func formatter(for format: String) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }

        if let existing = customFormatters[format] {
            return existing
        }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        customFormatters[format] = formatter
        return formatter
    }
}

// MARK: - Date Extensions
extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(self)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hr ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    func formatted(as format: String) -> String {
        Formatters.formatter(for: format).string(from: self)
    }

    var formattedTime: String {
        Formatters.time.string(from: self)
    }

    var formattedDate: String {
        Formatters.date.string(from: self)
    }

    var formattedDateTime: String {
        Formatters.dateTime.string(from: self)
    }
}

// MARK: - CLLocationCoordinate2D Extensions
extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let from = CLLocation(latitude: latitude, longitude: longitude)
        let to = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return from.distance(from: to)
    }

    var isValid: Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
    }
}

// MARK: - Color Extensions
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)  // Transparent black as fallback
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - String Extensions
extension String {
    var isValidSquadCode: Bool {
        count == 6 && allSatisfy { Constants.Squad.codeCharacters.contains($0) }
    }

    func truncated(to length: Int, trailing: String = "...") -> String {
        if count > length {
            return String(prefix(length)) + trailing
        }
        return self
    }
}

// MARK: - View Extensions
extension View {
    func hideKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Array Extensions
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Data Extensions
extension Data {
    var prettyPrintedJSON: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self),
              let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

// MARK: - UserDefaults Extensions
extension UserDefaults {
    func setCodable<T: Codable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            set(data, forKey: key)
        }
    }

    func codable<T: Codable>(forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Haptic Feedback
enum Haptics {
    #if os(iOS)
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    #endif

    /// Light tap feedback - use for subtle interactions
    static func light() {
        #if os(iOS)
        impactLight.impactOccurred()
        #endif
    }

    /// Medium tap feedback - use for standard button taps
    static func medium() {
        #if os(iOS)
        impactMedium.impactOccurred()
        #endif
    }

    /// Heavy tap feedback - use for significant actions
    static func heavy() {
        #if os(iOS)
        impactHeavy.impactOccurred()
        #endif
    }

    /// Success feedback - use for completed actions
    static func success() {
        #if os(iOS)
        notification.notificationOccurred(.success)
        #endif
    }

    /// Warning feedback - use for alerts/warnings
    static func warning() {
        #if os(iOS)
        notification.notificationOccurred(.warning)
        #endif
    }

    /// Error feedback - use for failed actions
    static func error() {
        #if os(iOS)
        notification.notificationOccurred(.error)
        #endif
    }

    /// Selection changed feedback - use for picker/toggle changes
    static func selection() {
        #if os(iOS)
        selectionGenerator.selectionChanged()
        #endif
    }
}
