import Foundation

// MARK: - Message Signer Protocol

/// Protocol for signing mesh messages. Implemented by MessageSigner (Task 3).
protocol MessageSignerProtocol {
    func sign(_ data: Data) throws -> Data
}

// MARK: - V2 Message Types

enum V2MessageType: String, Codable, CaseIterable {
    case presencePulse
    case locationRequest
    case locationResponse
    case preciseLocationRequest
    case preciseLocationResponse
    case stopPreciseLocation
    case requestRenewal
    case clusterHandoff
    case urgentChat
    case chat
    case squadAnnouncement
    case sos
    case sosCancelled

    /// Payload budget in bytes for this message type.
    var payloadBudget: Int {
        switch self {
        case .presencePulse:          return Constants.PayloadBudget.presencePulse
        case .locationRequest:        return Constants.PayloadBudget.locationRequest
        case .locationResponse:       return Constants.PayloadBudget.locationResponse
        case .preciseLocationRequest: return Constants.PayloadBudget.preciseLocationRequest
        case .preciseLocationResponse: return Constants.PayloadBudget.preciseLocationResponse
        case .stopPreciseLocation:    return Constants.PayloadBudget.stopPreciseLocation
        case .requestRenewal:         return Constants.PayloadBudget.requestRenewal
        case .clusterHandoff:         return Constants.PayloadBudget.clusterHandoff
        case .urgentChat:             return Constants.PayloadBudget.urgentChat
        case .chat:                   return Constants.PayloadBudget.chat
        case .squadAnnouncement:      return Constants.PayloadBudget.squadAnnouncement
        case .sos:                    return Constants.PayloadBudget.sos
        case .sosCancelled:           return Constants.PayloadBudget.sos // reuse SOS budget
        }
    }
}

// MARK: - Renewal Mode

enum RenewalMode: String, Codable {
    case ambient
    case precise
}

// MARK: - Payload Structs

struct V2PresencePulse: Codable {
    let userId: String
    let battery: Int
    let isOnline: Bool
    let clusterID: String?
    let clusterMembers: [String]?
}

struct V2LocationRequest: Codable {
    let requesterID: String
}

struct V2LocationResponse: Codable {
    let latitude: Double
    let longitude: Double
    let clusterID: String?
    let clusterMembers: [String]?
    let heading: Double?
}

struct V2PreciseLocationRequest: Codable {
    let requesterID: String
    let targetMemberID: String
}

struct V2PreciseLocationResponse: Codable {
    let latitude: Double
    let longitude: Double
    let heading: Double?
    let speed: Double?
    let accuracy: Double
}

struct V2StopPreciseLocation: Codable {
    let requesterID: String
}

struct V2RequestRenewal: Codable {
    let requesterID: String
    let mode: RenewalMode
}

struct V2ClusterHandoff: Codable {
    let lastLatitude: Double
    let lastLongitude: Double
    let lastAccuracy: Double
    let newReporterID: String
}

struct V2ChatPayload: Codable {
    let messageId: String
    let text: String
    let senderName: String
}

struct V2SquadAnnouncement: Codable {
    let announcementId: String
    let text: String
    let senderName: String
    let pinLatitude: Double?
    let pinLongitude: Double?
}

struct V2SOSPayload: Codable {
    let userId: String
    let latitude: Double
    let longitude: Double
    let heading: Double?
    let speed: Double?
}

struct V2SOSCancelled: Codable {
    let userId: String
}

// MARK: - V2 Envelope

struct V2Envelope: Codable {

    // MARK: Validation Errors

    enum ValidationError: Error, LocalizedError {
        case invalidVersion
        case invalidCoordinates
        case textTooLong
        case invalidMessageId
        case ttlOutOfRange
        case batteryOutOfRange
        case payloadTooLarge(type: String, size: Int, max: Int)

        var errorDescription: String? {
            switch self {
            case .invalidVersion:
                return "Envelope version does not match ProtocolV2.version"
            case .invalidCoordinates:
                return "Coordinates out of valid range (lat ±90, lon ±180)"
            case .textTooLong:
                return "Text exceeds 500-character limit"
            case .invalidMessageId:
                return "Message ID is invalid"
            case .ttlOutOfRange:
                return "TTL must be between 1 and 10"
            case .batteryOutOfRange:
                return "Battery level must be 0-100"
            case .payloadTooLarge(let type, let size, let max):
                return "Payload for \(type) is \(size) bytes (max \(max))"
            }
        }
    }

    // MARK: Fields

    let version: Int
    let messageId: UUID
    let type: V2MessageType
    let payload: Data
    let originPeerId: String
    let targetPeerId: String?
    let squadId: String
    let timestamp: Date
    var ttl: Int
    var visitedPeers: [String]
    let signature: Data

    // MARK: Validation

    /// Validates envelope-level fields: version, TTL, payload budget.
    func validate() throws {
        guard version == Constants.ProtocolV2.version else {
            throw ValidationError.invalidVersion
        }
        guard (1...10).contains(ttl) else {
            throw ValidationError.ttlOutOfRange
        }
        let budget = type.payloadBudget
        guard payload.count <= budget else {
            throw ValidationError.payloadTooLarge(
                type: type.rawValue,
                size: payload.count,
                max: budget
            )
        }
    }

    /// Decodes the payload per message type and validates domain constraints.
    func validatePayloadContent() throws {
        let decoder = JSONDecoder()

        switch type {
        case .presencePulse:
            let pulse = try decoder.decode(V2PresencePulse.self, from: payload)
            guard (0...100).contains(pulse.battery) else {
                throw ValidationError.batteryOutOfRange
            }

        case .locationRequest:
            _ = try decoder.decode(V2LocationRequest.self, from: payload)

        case .locationResponse:
            let resp = try decoder.decode(V2LocationResponse.self, from: payload)
            try Self.validateCoordinates(latitude: resp.latitude, longitude: resp.longitude)

        case .preciseLocationRequest:
            _ = try decoder.decode(V2PreciseLocationRequest.self, from: payload)

        case .preciseLocationResponse:
            let resp = try decoder.decode(V2PreciseLocationResponse.self, from: payload)
            try Self.validateCoordinates(latitude: resp.latitude, longitude: resp.longitude)

        case .stopPreciseLocation:
            _ = try decoder.decode(V2StopPreciseLocation.self, from: payload)

        case .requestRenewal:
            _ = try decoder.decode(V2RequestRenewal.self, from: payload)

        case .clusterHandoff:
            let handoff = try decoder.decode(V2ClusterHandoff.self, from: payload)
            try Self.validateCoordinates(latitude: handoff.lastLatitude, longitude: handoff.lastLongitude)

        case .urgentChat:
            let chat = try decoder.decode(V2ChatPayload.self, from: payload)
            guard chat.text.count <= 500 else {
                throw ValidationError.textTooLong
            }

        case .chat:
            let chat = try decoder.decode(V2ChatPayload.self, from: payload)
            guard chat.text.count <= 500 else {
                throw ValidationError.textTooLong
            }

        case .squadAnnouncement:
            let announcement = try decoder.decode(V2SquadAnnouncement.self, from: payload)
            guard announcement.text.count <= 500 else {
                throw ValidationError.textTooLong
            }
            if let lat = announcement.pinLatitude, let lon = announcement.pinLongitude {
                try Self.validateCoordinates(latitude: lat, longitude: lon)
            }

        case .sos:
            let sos = try decoder.decode(V2SOSPayload.self, from: payload)
            try Self.validateCoordinates(latitude: sos.latitude, longitude: sos.longitude)

        case .sosCancelled:
            _ = try decoder.decode(V2SOSCancelled.self, from: payload)
        }
    }

    // MARK: Forwarding

    /// Returns a copy with decremented TTL and appended peer, or nil if not forwardable.
    func forwarded(by peerId: String) -> V2Envelope? {
        guard ttl > 1, !visitedPeers.contains(peerId) else { return nil }
        var copy = self
        copy.ttl = ttl - 1
        copy.visitedPeers = visitedPeers + [peerId]
        return copy
    }

    // MARK: Encoding / Decoding

    /// Encodes the envelope to JSON Data.
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decodes from JSON Data and validates the result.
    static func decode(from data: Data) throws -> V2Envelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(V2Envelope.self, from: data)
        try envelope.validate()
        return envelope
    }

    // MARK: Private Helpers

    private static func validateCoordinates(latitude: Double, longitude: Double) throws {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw ValidationError.invalidCoordinates
        }
    }
}

// MARK: - V2 Envelope Builder

enum V2EnvelopeBuilder {

    /// Builds a signed V2Envelope.
    static func build<Payload: Encodable>(
        type: V2MessageType,
        payload: Payload,
        originPeerId: String,
        targetPeerId: String? = nil,
        squadId: String,
        signer: MessageSignerProtocol
    ) throws -> V2Envelope {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(payload)

        let messageId = UUID()
        let timestamp = Date()

        // Build signing input: messageId + payload + timestamp
        var signingData = Data()
        signingData.append(messageId.uuidString.data(using: .utf8)!)
        signingData.append(payloadData)
        let timestampString = ISO8601DateFormatter().string(from: timestamp)
        signingData.append(timestampString.data(using: .utf8)!)

        let signature = try signer.sign(signingData)

        return V2Envelope(
            version: Constants.ProtocolV2.version,
            messageId: messageId,
            type: type,
            payload: payloadData,
            originPeerId: originPeerId,
            targetPeerId: targetPeerId,
            squadId: squadId,
            timestamp: timestamp,
            ttl: Constants.Mesh.messageTTL,
            visitedPeers: [originPeerId],
            signature: signature
        )
    }
}

// MARK: - String Sanitization

extension String {
    /// Strips control characters (keeps printable + emoji) and truncates to 500 characters.
    var sanitizedForMesh: String {
        let cleaned = unicodeScalars.filter { scalar in
            // Keep printable characters: letters, numbers, punctuation, symbols, spaces, emoji
            !scalar.properties.isNoncharacterCodePoint &&
            (scalar.properties.isEmoji ||
             scalar.value >= 0x20 && scalar.value != 0x7F) // exclude C0 controls and DEL
        }
        let result = String(String.UnicodeScalarView(cleaned))
        if result.count > 500 {
            return String(result.prefix(500))
        }
        return result
    }
}
