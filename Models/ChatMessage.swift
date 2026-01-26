import Foundation
import SwiftData

// Forward reference to Location from User.swift
// Location is defined in User.swift

@Model
final class ChatMessage: Identifiable {
    @Attribute(.unique) var id: UUID
    var senderId: UUID
    var senderName: String
    var text: String
    var timestamp: Date
    var squadId: UUID
    var isDelivered: Bool
    var isSynced: Bool

    init(
        id: UUID = UUID(),
        senderId: UUID,
        senderName: String,
        text: String,
        squadId: UUID,
        timestamp: Date = Date(),
        isDelivered: Bool = false,
        isSynced: Bool = false
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.squadId = squadId
        self.timestamp = timestamp
        self.isDelivered = isDelivered
        self.isSynced = isSynced
    }
}

// MARK: - Mesh Message Wrapper
struct MeshMessagePayload: Codable {
    let type: MeshMessageType
    let userId: String?
    let location: LocationPayload?
    let chat: ChatMessagePayload?
    let peerId: String?
    let signalStrength: Int?
    let squadId: String?
    let syncData: Data?
    let batteryLevel: Int?
    let hasService: Bool?
    let enabled: Bool?
    let status: StatusPayload?
    let meetupPin: MeetupPinPayload?

    enum MeshMessageType: String, Codable {
        case locationUpdate
        case chatMessage
        case gatewayAnnounce
        case syncRequest
        case syncResponse
        case heartbeat
        case findMe
        case statusUpdate
        case meetupPin
    }

    struct LocationPayload: Codable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let timestamp: Date
        let source: String
    }

    struct ChatMessagePayload: Codable {
        let id: UUID
        let senderId: UUID
        let senderName: String
        let text: String
        let squadId: UUID
        let timestamp: Date
    }

    struct StatusPayload: Codable {
        let presetRawValue: String?
        let customText: String?
        let setAt: Date
        let expiresAt: Date?

        init(from status: UserStatus) {
            self.presetRawValue = status.preset?.rawValue
            self.customText = status.customText
            self.setAt = status.setAt
            self.expiresAt = status.expiresAt
        }

        func toUserStatus() -> UserStatus {
            UserStatus(
                preset: presetRawValue.flatMap { StatusPreset(rawValue: $0) },
                customText: customText,
                setAt: setAt,
                expiresAt: expiresAt
            )
        }
    }

    struct MeetupPinPayload: Codable {
        let id: UUID
        let latitude: Double
        let longitude: Double
        let name: String
        let creatorId: String
        let creatorName: String
        let createdAt: Date
        let expiresAt: Date
    }

    // Factory methods
    static func locationUpdate(userId: String, location: Location) -> MeshMessagePayload {
        MeshMessagePayload(
            type: .locationUpdate,
            userId: userId,
            location: LocationPayload(
                latitude: location.latitude,
                longitude: location.longitude,
                accuracy: location.accuracy,
                timestamp: location.timestamp,
                source: location.source.rawValue
            ),
            chat: nil, peerId: nil, signalStrength: nil, squadId: nil,
            syncData: nil, batteryLevel: nil, hasService: nil, enabled: nil,
            status: nil, meetupPin: nil
        )
    }

    static func gatewayAnnounce(peerId: String, signalStrength: Int) -> MeshMessagePayload {
        MeshMessagePayload(
            type: .gatewayAnnounce,
            userId: nil, location: nil, chat: nil,
            peerId: peerId, signalStrength: signalStrength,
            squadId: nil, syncData: nil, batteryLevel: nil, hasService: nil, enabled: nil,
            status: nil, meetupPin: nil
        )
    }

    static func heartbeat(userId: String, batteryLevel: Int, hasService: Bool) -> MeshMessagePayload {
        MeshMessagePayload(
            type: .heartbeat,
            userId: userId, location: nil, chat: nil, peerId: nil, signalStrength: nil,
            squadId: nil, syncData: nil, batteryLevel: batteryLevel, hasService: hasService, enabled: nil,
            status: nil, meetupPin: nil
        )
    }

    static func syncResponse(data: Data) -> MeshMessagePayload {
        MeshMessagePayload(
            type: .syncResponse,
            userId: nil, location: nil, chat: nil, peerId: nil, signalStrength: nil,
            squadId: nil, syncData: data, batteryLevel: nil, hasService: nil, enabled: nil,
            status: nil, meetupPin: nil
        )
    }

    static func statusUpdate(userId: String, displayName: String, status: UserStatus) -> MeshMessagePayload {
        MeshMessagePayload(
            type: .statusUpdate,
            userId: userId, location: nil, chat: nil, peerId: displayName, signalStrength: nil,
            squadId: nil, syncData: nil, batteryLevel: nil, hasService: nil, enabled: nil,
            status: StatusPayload(from: status), meetupPin: nil
        )
    }

    static func meetupPin(_ pin: MeetupPinPayload) -> MeshMessagePayload {
        MeshMessagePayload(
            type: .meetupPin,
            userId: pin.creatorId, location: nil, chat: nil, peerId: nil, signalStrength: nil,
            squadId: nil, syncData: nil, batteryLevel: nil, hasService: nil, enabled: nil,
            status: nil, meetupPin: pin
        )
    }
}

// MARK: - Message Envelope for Relay
/// Wraps messages for relay through the universal mesh network
/// Messages are relayed by ALL FestivAir users, but only decrypted by target squad
struct MeshEnvelope: Codable {
    let messageId: UUID
    let message: MeshMessagePayload
    let originPeerId: String
    var visitedPeers: [String]
    let ttl: Int
    let timestamp: Date

    // MARK: - Universal Relay Fields
    let targetSquadId: String?     // Which squad this message is for (nil = broadcast)
    let encryptedPayload: Data?    // Encrypted version for cross-squad relay

    /// Check if this message is for our squad
    var isForMySquad: Bool {
        guard let target = targetSquadId else { return true }  // Broadcast
        let mySquad = UserDefaults.standard.string(forKey: "FestivAir.CurrentSquadId")
        return target == mySquad
    }

    init(message: MeshMessagePayload, originPeerId: String, ttl: Int = 10, targetSquadId: String? = nil, encryptedPayload: Data? = nil) {
        self.messageId = UUID()
        self.message = message
        self.originPeerId = originPeerId
        self.visitedPeers = [originPeerId]
        self.ttl = ttl
        self.timestamp = Date()
        self.targetSquadId = targetSquadId
        self.encryptedPayload = encryptedPayload
    }

    /// Create a forwarded copy for relay (used by other users to pass along)
    func forwarded(by peerId: String) -> MeshEnvelope? {
        guard ttl > 1, !visitedPeers.contains(peerId) else { return nil }
        return MeshEnvelope(
            messageId: messageId,
            message: message,
            originPeerId: originPeerId,
            visitedPeers: visitedPeers + [peerId],
            ttl: ttl - 1,
            timestamp: timestamp,
            targetSquadId: targetSquadId,
            encryptedPayload: encryptedPayload
        )
    }

    private init(messageId: UUID, message: MeshMessagePayload, originPeerId: String, visitedPeers: [String], ttl: Int, timestamp: Date, targetSquadId: String?, encryptedPayload: Data?) {
        self.messageId = messageId
        self.message = message
        self.originPeerId = originPeerId
        self.visitedPeers = visitedPeers
        self.ttl = ttl
        self.timestamp = timestamp
        self.targetSquadId = targetSquadId
        self.encryptedPayload = encryptedPayload
    }
}
