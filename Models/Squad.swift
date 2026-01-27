import Foundation
import SwiftData

@Model
final class Squad {
    @Attribute(.unique) var id: UUID
    var name: String
    var joinCode: String
    var createdAt: Date
    var currentEventId: String?
    var firebaseId: String?

    @Relationship(deleteRule: .nullify, inverse: \SquadMembership.squad)
    var memberships: [SquadMembership]?

    init(
        id: UUID = UUID(),
        name: String,
        joinCode: String = Squad.generateJoinCode(),
        createdAt: Date = Date(),
        currentEventId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.joinCode = joinCode
        self.createdAt = createdAt
        self.currentEventId = currentEventId
    }

    static func generateJoinCode() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // No O, 0, I, 1 to avoid confusion
        return String((0..<6).compactMap { _ in characters.randomElement() })
    }

    var memberCount: Int {
        memberships?.count ?? 0
    }

    var isAtCapacity: Bool {
        memberCount >= Constants.Squad.maxMembers
    }
}

// MARK: - Squad Membership (Join Table)
@Model
final class SquadMembership: Identifiable {
    @Attribute(.unique) var id: UUID
    var joinedAt: Date
    var isAdmin: Bool
    var user: User?
    var squad: Squad?

    init(
        id: UUID = UUID(),
        user: User,
        squad: Squad,
        joinedAt: Date = Date(),
        isAdmin: Bool = false
    ) {
        self.id = id
        self.user = user
        self.squad = squad
        self.joinedAt = joinedAt
        self.isAdmin = isAdmin
    }
}
