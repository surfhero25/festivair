import Foundation
import SwiftData

// Forward reference to Location from User.swift
// Location is defined in User.swift

@Model
final class ChatMessage {
    var id: UUID
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

    enum MeshMessageType: String, Codable {
        case locationUpdate
        case chatMessage
        case gatewayAnnounce
        case syncRequest
        case syncResponse
        case heartbeat
        case findMe
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
            syncData: nil, batteryLevel: nil, hasService: nil, enabled: nil
        )
    }

    static func gatewayAnnounce(peerId: String, signalStrength: Int) -> MeshMessagePayload {
        MeshMessagePayload(
            type: .gatewayAnnounce,
            userId: nil, location: nil, chat: nil,
            peerId: peerId, signalStrength: signalStrength,
            squadId: nil, syncData: nil, batteryLevel: nil, hasService: nil, enabled: nil
        )
    }

    static func heartbeat(userId: String, batteryLevel: Int, hasService: Bool) -> MeshMessagePayload {
        MeshMessagePayload(
            type: .heartbeat,
            userId: userId, location: nil, chat: nil, peerId: nil, signalStrength: nil,
            squadId: nil, syncData: nil, batteryLevel: batteryLevel, hasService: hasService, enabled: nil
        )
    }

    static func syncResponse(data: Data) -> MeshMessagePayload {
        MeshMessagePayload(
            type: .syncResponse,
            userId: nil, location: nil, chat: nil, peerId: nil, signalStrength: nil,
            squadId: nil, syncData: data, batteryLevel: nil, hasService: nil, enabled: nil
        )
    }
}

// MARK: - Message Envelope for Relay
struct MeshEnvelope: Codable {
    let messageId: UUID
    let message: MeshMessagePayload
    let originPeerId: String
    var visitedPeers: [String]
    let ttl: Int
    let timestamp: Date

    init(message: MeshMessagePayload, originPeerId: String, ttl: Int = 3) {
        self.messageId = UUID()
        self.message = message
        self.originPeerId = originPeerId
        self.visitedPeers = [originPeerId]
        self.ttl = ttl
        self.timestamp = Date()
    }

    func forwarded(by peerId: String) -> MeshEnvelope? {
        guard ttl > 1, !visitedPeers.contains(peerId) else { return nil }
        return MeshEnvelope(
            messageId: messageId,
            message: message,
            originPeerId: originPeerId,
            visitedPeers: visitedPeers + [peerId],
            ttl: ttl - 1,
            timestamp: timestamp
        )
    }

    private init(messageId: UUID, message: MeshMessagePayload, originPeerId: String, visitedPeers: [String], ttl: Int, timestamp: Date) {
        self.messageId = messageId
        self.message = message
        self.originPeerId = originPeerId
        self.visitedPeers = visitedPeers
        self.ttl = ttl
        self.timestamp = timestamp
    }
}
