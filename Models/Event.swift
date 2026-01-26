import Foundation
import SwiftData

@Model
final class Event {
    @Attribute(.unique) var id: String
    var name: String
    var venue: String
    var city: String
    var startDate: Date
    var endDate: Date
    var imageUrl: String?
    var websiteUrl: String?

    @Relationship(deleteRule: .cascade, inverse: \Stage.event)
    var stages: [Stage]?

    init(
        id: String,
        name: String,
        venue: String,
        city: String,
        startDate: Date,
        endDate: Date,
        imageUrl: String? = nil,
        websiteUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.venue = venue
        self.city = city
        self.startDate = startDate
        self.endDate = endDate
        self.imageUrl = imageUrl
        self.websiteUrl = websiteUrl
    }

    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    var daysRemaining: Int? {
        let now = Date()
        guard startDate > now else { return nil }
        return Calendar.current.dateComponents([.day], from: now, to: startDate).day
    }
}

@Model
final class Stage: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var color: String // Hex color for map/UI
    var event: Event?

    @Relationship(deleteRule: .cascade, inverse: \SetTime.stage)
    var setTimes: [SetTime]?

    init(
        id: UUID = UUID(),
        name: String,
        color: String = "#8B5CF6"
    ) {
        self.id = id
        self.name = name
        self.color = color
    }
}
