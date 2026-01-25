import Foundation
import SwiftData

@Model
final class SetTime {
    var id: UUID
    var artistName: String
    var startTime: Date
    var endTime: Date
    var isFavorite: Bool
    var notificationScheduled: Bool
    var stage: Stage?

    init(
        id: UUID = UUID(),
        artistName: String,
        startTime: Date,
        endTime: Date,
        isFavorite: Bool = false,
        notificationScheduled: Bool = false
    ) {
        self.id = id
        self.artistName = artistName
        self.startTime = startTime
        self.endTime = endTime
        self.isFavorite = isFavorite
        self.notificationScheduled = notificationScheduled
    }

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }

    var isLive: Bool {
        let now = Date()
        return now >= startTime && now <= endTime
    }

    var isUpcoming: Bool {
        Date() < startTime
    }

    var minutesUntilStart: Int? {
        guard isUpcoming else { return nil }
        return Int(startTime.timeIntervalSinceNow / 60)
    }

    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
}

// MARK: - Conflict Detection
extension Array where Element == SetTime {
    func conflicts(with setTime: SetTime) -> [SetTime] {
        filter { other in
            guard other.id != setTime.id else { return false }
            // Check for time overlap
            return setTime.startTime < other.endTime && setTime.endTime > other.startTime
        }
    }

    var favoriteConflicts: [(SetTime, SetTime)] {
        let favorites = filter { $0.isFavorite }
        var conflicts: [(SetTime, SetTime)] = []

        for i in 0..<favorites.count {
            for j in (i+1)..<favorites.count {
                let a = favorites[i]
                let b = favorites[j]
                if a.startTime < b.endTime && a.endTime > b.startTime {
                    conflicts.append((a, b))
                }
            }
        }
        return conflicts
    }
}
