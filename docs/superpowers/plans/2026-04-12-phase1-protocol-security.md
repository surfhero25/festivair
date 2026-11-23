# Phase 1: Protocol V2 & Security Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken mesh protocol with Protocol V2 — signed, encrypted, validated messages with proper key management. This is the foundation everything else builds on.

**Architecture:** New message type definitions in `MeshProtocolV2.swift`, P-256 Secure Enclave signing in `MessageSigner.swift`, squad secret-based AES-GCM encryption replacing SHA256(squadId), PII migrated from UserDefaults to Keychain, join codes increased to 8 chars with uniqueness validation.

**Tech Stack:** Swift, CryptoKit, Security framework (Secure Enclave), CloudKit, SwiftData

**Spec:** `docs/superpowers/specs/2026-04-12-demand-driven-location-design.md`

**Phase dependency:** None — this is the foundation.

---

## File Map

### New Files
| File | Responsibility |
|---|---|
| `Models/MeshProtocolV2.swift` | All V2 message types, envelope, encode/decode with built-in validation, payload budget enforcement |
| `Services/MessageSigner.swift` | P-256 keypair lifecycle (Secure Enclave), sign message, verify signature |
| `Tests/MeshProtocolV2Tests.swift` | Protocol encode/decode, validation, payload budgets |
| `Tests/MessageSignerTests.swift` | Signing round-trip, invalid signature rejection |
| `Tests/SquadSecretTests.swift` | Secret generation, encryption round-trip, key rotation |

### Modified Files
| File | Change Summary |
|---|---|
| `Utilities/Constants.swift` | Add V2 timing constants, battery tiers, payload budgets. Update join code length to 8. |
| `Utilities/KeychainHelper.swift` | Add keys for squadSecret, signingKeyTag. Change accessibility to `whenUnlockedThisDeviceOnly`. Remove `restoreToUserDefaults()`. |
| `Services/MeshRelayService.swift` | Replace `getSquadKey()` SHA256 derivation with Keychain-based squad secret. Update encrypt/decrypt. |
| `Services/MeshNetworkManager.swift` | Replace `seenMessageIds` Array with Set. Add `sendDirect(to:)` for peer-specific messages. Integrate message signing. |
| `Services/CloudKitService.swift` | Add `squadSecret` field to squad record. Validate join code uniqueness. Increase code to 8 chars. Add `squadTier` field. |
| `Models/Squad.swift` | Update `generateJoinCode()` to 8 chars. |
| `Models/ChatMessage.swift` | Keep existing types for backward compat during migration. Add V2 import path. |
| `App/FestivAirApp.swift` | Remove `restoreToUserDefaults()` call. Load all identity from Keychain. |
| `App/AppDelegate.swift` | Fix force casts to conditional casts. Update URL scheme for 8-char codes. |

---

## Task 1: Update Constants

**Files:**
- Modify: `Utilities/Constants.swift`

- [ ] **Step 1: Add Protocol V2 constants**

Open `Utilities/Constants.swift` and add the following sections. Keep all existing constants — V1 code still references them during migration.

```swift
// Add after the existing MeshRelay section (after line ~103)

// MARK: - Protocol V2

enum ProtocolV2 {
    static let version: Int = 2
    static let presencePulseInterval: TimeInterval = 300       // 5 minutes
    static let ambientResponseInterval: TimeInterval = 60      // 1 minute
    static let ambientResponseReducedInterval: TimeInterval = 90 // 1.5 min (battery 30-50%)
    static let preciseResponseInterval: TimeInterval = 3       // 3 seconds
    static let requestRenewalInterval: TimeInterval = 60       // 1 minute
    static let sessionTimeout: TimeInterval = 90               // drop state after no renewal
    static let stalePinMaxAge: TimeInterval = 3600             // 1 hour — hide pins older than this
    static let stalePinFadeAge: TimeInterval = 300             // 5 min — start fading
    static let chatFallbackDelay: TimeInterval = 30            // send standalone if no mesh activity
    static let urgentChatRateLimit: Int = 5                    // max per 10 minutes
    static let urgentChatRateWindow: TimeInterval = 600        // 10 minutes
    static let sosUpdateInterval: TimeInterval = 3             // SOS broadcasts every 3s
}

// MARK: - Payload Budgets (bytes)

enum PayloadBudget {
    static let presencePulse: Int = 100
    static let locationRequest: Int = 50
    static let locationResponse: Int = 200
    static let preciseLocationRequest: Int = 80
    static let preciseLocationResponse: Int = 150
    static let urgentChat: Int = 500
    static let chat: Int = 500
    static let squadAnnouncement: Int = 1000
    static let sos: Int = 150
    static let stopPreciseLocation: Int = 50
    static let requestRenewal: Int = 80
    static let clusterHandoff: Int = 200
}

// MARK: - Battery Tiers

enum BatteryTier {
    static let fullMin: Float = 0.50        // 50-100%: full participation
    static let reducedMin: Float = 0.30     // 30-50%: reduced
    static let passiveMin: Float = 0.15     // 15-30%: passive only
    // Below 15%: survival mode

    static func tier(for level: Float) -> Tier {
        switch level {
        case fullMin...1.0: return .full
        case reducedMin..<fullMin: return .reduced
        case passiveMin..<reducedMin: return .passive
        default: return .survival
        }
    }

    enum Tier: String, Codable {
        case full, reduced, passive, survival
    }
}
```

- [ ] **Step 2: Update Squad constants**

```swift
// Replace existing Squad section (lines ~84-94)
enum Squad {
    static let maxMembers = 50
    static let codeLength = 8  // Changed from 6
    static let codeCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    static let freeMemberLimit = 4
    static let festivalPassMemberLimit = 8
    static let crewPassMemberLimit = 20
    static let seasonPassMemberLimit = 20
    static let joinAttemptRateLimit = 3          // per minute
    static let joinAttemptRateWindow: TimeInterval = 60
}
```

- [ ] **Step 3: Build to verify no compiler errors**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED (existing code still compiles — we only added new constants)

- [ ] **Step 4: Commit**

```bash
git add Utilities/Constants.swift
git commit -m "feat: add Protocol V2 constants, battery tiers, payload budgets, 8-char join codes"
```

---

## Task 2: MeshProtocolV2 Message Types

**Files:**
- Create: `Models/MeshProtocolV2.swift`
- Create: `Tests/MeshProtocolV2Tests.swift`

- [ ] **Step 1: Create the V2 message type enum and envelope**

Create `Models/MeshProtocolV2.swift`:

```swift
import Foundation

// MARK: - V2 Message Types

enum V2MessageType: String, Codable {
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
}

// MARK: - V2 Payloads

struct V2PresencePulse: Codable {
    let userId: String
    let battery: Int          // 0-100
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

    enum RenewalMode: String, Codable {
        case ambient
        case precise
    }
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
    let version: Int
    let messageId: UUID
    let type: V2MessageType
    let payload: Data          // Encoded payload struct
    let originPeerId: String
    let targetPeerId: String?  // nil = broadcast, set = direct
    let squadId: String
    let timestamp: Date
    let ttl: Int
    var visitedPeers: [String]
    let signature: Data        // P-256 signature over (messageId + payload + timestamp)

    // MARK: - Validation

    enum ValidationError: Error {
        case invalidCoordinates
        case textTooLong
        case invalidMessageId
        case ttlOutOfRange
        case batteryOutOfRange
        case payloadTooLarge(type: V2MessageType, size: Int, max: Int)
        case invalidVersion
    }

    func validate() throws {
        guard version == Constants.ProtocolV2.version else {
            throw ValidationError.invalidVersion
        }
        guard (1...10).contains(ttl) else {
            throw ValidationError.ttlOutOfRange
        }

        // Payload budget check
        let maxSize = payloadBudget(for: type)
        guard payload.count <= maxSize else {
            throw ValidationError.payloadTooLarge(type: type, size: payload.count, max: maxSize)
        }
    }

    func validatePayloadContent() throws {
        switch type {
        case .presencePulse:
            let p = try JSONDecoder().decode(V2PresencePulse.self, from: payload)
            guard (0...100).contains(p.battery) else { throw ValidationError.batteryOutOfRange }
        case .locationResponse:
            let p = try JSONDecoder().decode(V2LocationResponse.self, from: payload)
            try validateCoordinates(lat: p.latitude, lng: p.longitude)
        case .preciseLocationResponse:
            let p = try JSONDecoder().decode(V2PreciseLocationResponse.self, from: payload)
            try validateCoordinates(lat: p.latitude, lng: p.longitude)
        case .urgentChat, .chat:
            let p = try JSONDecoder().decode(V2ChatPayload.self, from: payload)
            guard p.text.count <= 500 else { throw ValidationError.textTooLong }
        case .squadAnnouncement:
            let p = try JSONDecoder().decode(V2SquadAnnouncement.self, from: payload)
            guard p.text.count <= 500 else { throw ValidationError.textTooLong }
            if let lat = p.pinLatitude, let lng = p.pinLongitude {
                try validateCoordinates(lat: lat, lng: lng)
            }
        case .sos:
            let p = try JSONDecoder().decode(V2SOSPayload.self, from: payload)
            try validateCoordinates(lat: p.latitude, lng: p.longitude)
        default:
            break
        }
    }

    private func validateCoordinates(lat: Double, lng: Double) throws {
        guard (-90...90).contains(lat), (-180...180).contains(lng) else {
            throw ValidationError.invalidCoordinates
        }
    }

    private func payloadBudget(for type: V2MessageType) -> Int {
        switch type {
        case .presencePulse: return Constants.PayloadBudget.presencePulse
        case .locationRequest: return Constants.PayloadBudget.locationRequest
        case .locationResponse: return Constants.PayloadBudget.locationResponse
        case .preciseLocationRequest: return Constants.PayloadBudget.preciseLocationRequest
        case .preciseLocationResponse: return Constants.PayloadBudget.preciseLocationResponse
        case .urgentChat: return Constants.PayloadBudget.urgentChat
        case .chat: return Constants.PayloadBudget.chat
        case .squadAnnouncement: return Constants.PayloadBudget.squadAnnouncement
        case .sos: return Constants.PayloadBudget.sos
        case .sosCancelled: return Constants.PayloadBudget.sos
        case .stopPreciseLocation: return Constants.PayloadBudget.stopPreciseLocation
        case .requestRenewal: return Constants.PayloadBudget.requestRenewal
        case .clusterHandoff: return Constants.PayloadBudget.clusterHandoff
        }
    }

    // MARK: - Forwarding (for relay)

    func forwarded(by peerId: String) -> V2Envelope? {
        guard ttl > 1, !visitedPeers.contains(peerId) else { return nil }
        var copy = self
        copy.visitedPeers.append(peerId)
        return V2Envelope(
            version: version,
            messageId: messageId,
            type: type,
            payload: payload,
            originPeerId: originPeerId,
            targetPeerId: targetPeerId,
            squadId: squadId,
            timestamp: timestamp,
            ttl: ttl - 1,
            visitedPeers: copy.visitedPeers,
            signature: signature
        )
    }

    // MARK: - Encoding

    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(from data: Data) throws -> V2Envelope {
        let envelope = try JSONDecoder().decode(V2Envelope.self, from: data)
        try envelope.validate()
        return envelope
    }
}

// MARK: - Envelope Builder

enum V2EnvelopeBuilder {
    static func build(
        type: V2MessageType,
        payload: some Encodable,
        originPeerId: String,
        targetPeerId: String? = nil,
        squadId: String,
        signer: MessageSigner
    ) throws -> V2Envelope {
        let payloadData = try JSONEncoder().encode(payload)
        let messageId = UUID()
        let timestamp = Date()

        // Sign: messageId + payload + timestamp
        let signatureInput = messageId.uuidString.data(using: .utf8)! + payloadData + "\(timestamp.timeIntervalSince1970)".data(using: .utf8)!
        let signature = try signer.sign(signatureInput)

        let envelope = V2Envelope(
            version: Constants.ProtocolV2.version,
            messageId: messageId,
            type: type,
            payload: payloadData,
            originPeerId: originPeerId,
            targetPeerId: targetPeerId,
            squadId: squadId,
            timestamp: timestamp,
            ttl: 3,
            visitedPeers: [originPeerId],
            signature: signature
        )

        try envelope.validate()
        return envelope
    }
}

// MARK: - Text Sanitization

extension String {
    var sanitizedForMesh: String {
        let stripped = self.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20 }
        return String(String.UnicodeScalarView(stripped)).prefix(500).description
    }
}
```

- [ ] **Step 2: Write tests for V2 message encoding/decoding and validation**

Create `Tests/MeshProtocolV2Tests.swift`:

```swift
import XCTest
@testable import FestivAir

final class MeshProtocolV2Tests: XCTestCase {

    // MARK: - Presence Pulse

    func testPresencePulseEncodeDecode() throws {
        let pulse = V2PresencePulse(userId: "user1", battery: 85, isOnline: true, clusterID: nil, clusterMembers: nil)
        let data = try JSONEncoder().encode(pulse)
        let decoded = try JSONDecoder().decode(V2PresencePulse.self, from: data)
        XCTAssertEqual(decoded.userId, "user1")
        XCTAssertEqual(decoded.battery, 85)
        XCTAssertTrue(decoded.isOnline)
    }

    func testPresencePulsePayloadUnderBudget() throws {
        let pulse = V2PresencePulse(userId: UUID().uuidString, battery: 100, isOnline: true, clusterID: UUID().uuidString, clusterMembers: ["a", "b", "c", "d"])
        let data = try JSONEncoder().encode(pulse)
        XCTAssertLessThanOrEqual(data.count, Constants.PayloadBudget.presencePulse)
    }

    // MARK: - Location Response

    func testLocationResponseValidCoordinates() throws {
        let response = V2LocationResponse(latitude: 40.7128, longitude: -74.0060, clusterID: nil, clusterMembers: nil, heading: 90.0)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(V2LocationResponse.self, from: data)
        XCTAssertEqual(decoded.latitude, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(decoded.longitude, -74.0060, accuracy: 0.0001)
    }

    // MARK: - Envelope Validation

    func testEnvelopeRejectsTTLOutOfRange() {
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .presencePulse,
            payload: Data(), originPeerId: "p1", targetPeerId: nil,
            squadId: "sq1", timestamp: Date(), ttl: 0,
            visitedPeers: ["p1"], signature: Data()
        )
        XCTAssertThrowsError(try envelope.validate()) { error in
            guard case V2Envelope.ValidationError.ttlOutOfRange = error else {
                XCTFail("Expected ttlOutOfRange, got \(error)")
                return
            }
        }
    }

    func testEnvelopeRejectsTTLAbove10() {
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .presencePulse,
            payload: Data(), originPeerId: "p1", targetPeerId: nil,
            squadId: "sq1", timestamp: Date(), ttl: 11,
            visitedPeers: ["p1"], signature: Data()
        )
        XCTAssertThrowsError(try envelope.validate())
    }

    func testEnvelopeRejectsWrongVersion() {
        let envelope = V2Envelope(
            version: 1, messageId: UUID(), type: .presencePulse,
            payload: Data(), originPeerId: "p1", targetPeerId: nil,
            squadId: "sq1", timestamp: Date(), ttl: 3,
            visitedPeers: ["p1"], signature: Data()
        )
        XCTAssertThrowsError(try envelope.validate()) { error in
            guard case V2Envelope.ValidationError.invalidVersion = error else {
                XCTFail("Expected invalidVersion, got \(error)")
                return
            }
        }
    }

    func testEnvelopeRejectsOversizedPayload() {
        let bigPayload = Data(repeating: 0x41, count: 1000)
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .presencePulse,
            payload: bigPayload, originPeerId: "p1", targetPeerId: nil,
            squadId: "sq1", timestamp: Date(), ttl: 3,
            visitedPeers: ["p1"], signature: Data()
        )
        XCTAssertThrowsError(try envelope.validate()) { error in
            guard case V2Envelope.ValidationError.payloadTooLarge = error else {
                XCTFail("Expected payloadTooLarge, got \(error)")
                return
            }
        }
    }

    // MARK: - Content Validation

    func testRejectsInvalidLatitude() throws {
        let response = V2LocationResponse(latitude: 91.0, longitude: 0.0, clusterID: nil, clusterMembers: nil, heading: nil)
        let data = try JSONEncoder().encode(response)
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .locationResponse,
            payload: data, originPeerId: "p1", targetPeerId: "p2",
            squadId: "sq1", timestamp: Date(), ttl: 3,
            visitedPeers: ["p1"], signature: Data()
        )
        XCTAssertThrowsError(try envelope.validatePayloadContent()) { error in
            guard case V2Envelope.ValidationError.invalidCoordinates = error else {
                XCTFail("Expected invalidCoordinates, got \(error)")
                return
            }
        }
    }

    func testRejectsInvalidLongitude() throws {
        let response = V2LocationResponse(latitude: 0.0, longitude: 181.0, clusterID: nil, clusterMembers: nil, heading: nil)
        let data = try JSONEncoder().encode(response)
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .locationResponse,
            payload: data, originPeerId: "p1", targetPeerId: "p2",
            squadId: "sq1", timestamp: Date(), ttl: 3,
            visitedPeers: ["p1"], signature: Data()
        )
        XCTAssertThrowsError(try envelope.validatePayloadContent())
    }

    func testRejectsChatTextOver500Chars() throws {
        let longText = String(repeating: "A", count: 501)
        let chat = V2ChatPayload(messageId: UUID().uuidString, text: longText, senderName: "Test")
        let data = try JSONEncoder().encode(chat)
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .chat,
            payload: data, originPeerId: "p1", targetPeerId: nil,
            squadId: "sq1", timestamp: Date(), ttl: 3,
            visitedPeers: ["p1"], signature: Data()
        )
        XCTAssertThrowsError(try envelope.validatePayloadContent()) { error in
            guard case V2Envelope.ValidationError.textTooLong = error else {
                XCTFail("Expected textTooLong, got \(error)")
                return
            }
        }
    }

    func testRejectsBatteryOutOfRange() throws {
        let pulse = V2PresencePulse(userId: "u1", battery: 101, isOnline: true, clusterID: nil, clusterMembers: nil)
        let data = try JSONEncoder().encode(pulse)
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .presencePulse,
            payload: data, originPeerId: "p1", targetPeerId: nil,
            squadId: "sq1", timestamp: Date(), ttl: 3,
            visitedPeers: ["p1"], signature: Data()
        )
        XCTAssertThrowsError(try envelope.validatePayloadContent())
    }

    // MARK: - Forwarding

    func testForwardDecrementssTTL() {
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .presencePulse,
            payload: Data(), originPeerId: "p1", targetPeerId: nil,
            squadId: "sq1", timestamp: Date(), ttl: 3,
            visitedPeers: ["p1"], signature: Data()
        )
        let forwarded = envelope.forwarded(by: "p2")
        XCTAssertNotNil(forwarded)
        XCTAssertEqual(forwarded!.ttl, 2)
        XCTAssertTrue(forwarded!.visitedPeers.contains("p2"))
    }

    func testForwardRejectsWhenTTLIs1() {
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .presencePulse,
            payload: Data(), originPeerId: "p1", targetPeerId: nil,
            squadId: "sq1", timestamp: Date(), ttl: 1,
            visitedPeers: ["p1"], signature: Data()
        )
        XCTAssertNil(envelope.forwarded(by: "p2"))
    }

    func testForwardRejectsAlreadyVisitedPeer() {
        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .presencePulse,
            payload: Data(), originPeerId: "p1", targetPeerId: nil,
            squadId: "sq1", timestamp: Date(), ttl: 5,
            visitedPeers: ["p1", "p2"], signature: Data()
        )
        XCTAssertNil(envelope.forwarded(by: "p2"))
    }

    // MARK: - Text Sanitization

    func testSanitizationStripsControlCharacters() {
        let dirty = "Hello\u{0000}World\u{007F}Test"
        let clean = dirty.sanitizedForMesh
        XCTAssertFalse(clean.contains("\u{0000}"))
        XCTAssertFalse(clean.contains("\u{007F}"))
        XCTAssertTrue(clean.contains("Hello"))
        XCTAssertTrue(clean.contains("World"))
    }

    func testSanitizationTruncatesAt500() {
        let long = String(repeating: "A", count: 600)
        let clean = long.sanitizedForMesh
        XCTAssertEqual(clean.count, 500)
    }

    // MARK: - Full Round Trip

    func testEnvelopeFullRoundTrip() throws {
        let pulse = V2PresencePulse(userId: "user1", battery: 75, isOnline: true, clusterID: nil, clusterMembers: nil)
        let payloadData = try JSONEncoder().encode(pulse)

        let envelope = V2Envelope(
            version: 2, messageId: UUID(), type: .presencePulse,
            payload: payloadData, originPeerId: "peer1", targetPeerId: nil,
            squadId: "squad1", timestamp: Date(), ttl: 3,
            visitedPeers: ["peer1"], signature: Data()
        )

        let encoded = try envelope.encode()
        let decoded = try V2Envelope.decode(from: encoded)

        XCTAssertEqual(decoded.type, .presencePulse)
        XCTAssertEqual(decoded.originPeerId, "peer1")
        XCTAssertEqual(decoded.ttl, 3)

        let decodedPulse = try JSONDecoder().decode(V2PresencePulse.self, from: decoded.payload)
        XCTAssertEqual(decodedPulse.userId, "user1")
        XCTAssertEqual(decodedPulse.battery, 75)
    }
}
```

- [ ] **Step 3: Add test files to Xcode project and run tests**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild test -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FestivAirTests/MeshProtocolV2Tests 2>&1 | grep -E '(Test Case|Tests|BUILD|error:)'`

Expected: All tests pass. If there's no test target yet, create one first:
```bash
# If no test target exists, the tests may need to be added via Xcode project
# or we add them directly and configure the build
```

- [ ] **Step 4: Commit**

```bash
git add Models/MeshProtocolV2.swift Tests/MeshProtocolV2Tests.swift
git commit -m "feat: add MeshProtocolV2 message types with validation and payload budgets"
```

---

## Task 3: MessageSigner (Secure Enclave P-256)

**Files:**
- Create: `Services/MessageSigner.swift`
- Create: `Tests/MessageSignerTests.swift`

- [ ] **Step 1: Create MessageSigner**

Create `Services/MessageSigner.swift`:

```swift
import Foundation
import CryptoKit

final class MessageSigner {

    private static let keyTag = "com.festivair.signing-key"

    // MARK: - Key Management

    /// Returns existing key or creates a new one in Secure Enclave.
    /// Falls back to CryptoKit P256 if Secure Enclave unavailable (Simulator).
    private var privateKey: SecureEnclave.P256.Signing.PrivateKey? {
        if let existing = loadKey() { return existing }
        return try? createKey()
    }

    private var fallbackKey: P256.Signing.PrivateKey?

    var publicKeyData: Data {
        if let key = privateKey {
            return key.publicKey.derRepresentation
        }
        if fallbackKey == nil {
            fallbackKey = loadOrCreateFallbackKey()
        }
        return fallbackKey!.publicKey.derRepresentation
    }

    // MARK: - Secure Enclave Key

    private func createKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        let key = try SecureEnclave.P256.Signing.PrivateKey(
            compactRepresentable: false,
            accessControl: accessControl(),
            authenticationContext: nil
        )
        // Store data representation in Keychain so we can reload it
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keyTag,
            kSecAttrAccount as String: "signing-key-data",
            kSecValueData as String: key.dataRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
        return key
    }

    private func loadKey() -> SecureEnclave.P256.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keyTag,
            kSecAttrAccount as String: "signing-key-data",
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data, authenticationContext: nil)
    }

    private func accessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [],
            &error
        ) else {
            throw error!.takeRetainedValue() as Error
        }
        return access
    }

    // MARK: - Simulator Fallback (non-Secure Enclave)

    private func loadOrCreateFallbackKey() -> P256.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keyTag,
            kSecAttrAccount as String: "fallback-signing-key",
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let key = try? P256.Signing.PrivateKey(rawRepresentation: data) {
            return key
        }

        let newKey = P256.Signing.PrivateKey()
        let storeQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keyTag,
            kSecAttrAccount as String: "fallback-signing-key",
            kSecValueData as String: newKey.rawRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(storeQuery as CFDictionary)
        SecItemAdd(storeQuery as CFDictionary, nil)
        return newKey
    }

    // MARK: - Sign & Verify

    func sign(_ data: Data) throws -> Data {
        if let key = privateKey {
            let signature = try key.signature(for: data)
            return signature.derRepresentation
        }
        // Simulator fallback
        if fallbackKey == nil {
            fallbackKey = loadOrCreateFallbackKey()
        }
        let signature = try fallbackKey!.signature(for: data)
        return signature.derRepresentation
    }

    static func verify(signature: Data, data: Data, publicKey: Data) -> Bool {
        guard let pubKey = try? P256.Signing.PublicKey(derRepresentation: publicKey),
              let sig = try? P256.Signing.ECDSASignature(derRepresentation: signature) else {
            return false
        }
        return pubKey.isValidSignature(sig, for: data)
    }

    // MARK: - Key Deletion (for testing / account reset)

    func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keyTag
        ]
        SecItemDelete(query as CFDictionary)
        fallbackKey = nil
    }
}
```

- [ ] **Step 2: Write tests for signing**

Create `Tests/MessageSignerTests.swift`:

```swift
import XCTest
@testable import FestivAir

final class MessageSignerTests: XCTestCase {

    var signer: MessageSigner!

    override func setUp() {
        super.setUp()
        signer = MessageSigner()
        signer.deleteKey()  // Start fresh
    }

    override func tearDown() {
        signer.deleteKey()
        super.tearDown()
    }

    func testSignAndVerifyRoundTrip() throws {
        let data = "Hello, FestivAir!".data(using: .utf8)!
        let signature = try signer.sign(data)
        let publicKey = signer.publicKeyData

        XCTAssertTrue(MessageSigner.verify(signature: signature, data: data, publicKey: publicKey))
    }

    func testVerifyRejectsTamperedData() throws {
        let data = "Original message".data(using: .utf8)!
        let signature = try signer.sign(data)
        let publicKey = signer.publicKeyData

        let tampered = "Tampered message".data(using: .utf8)!
        XCTAssertFalse(MessageSigner.verify(signature: tampered, data: data, publicKey: publicKey))
        XCTAssertFalse(MessageSigner.verify(signature: signature, data: tampered, publicKey: publicKey))
    }

    func testVerifyRejectsWrongPublicKey() throws {
        let data = "Test message".data(using: .utf8)!
        let signature = try signer.sign(data)

        // Create a different signer with different key
        let otherSigner = MessageSigner()
        otherSigner.deleteKey()
        let _ = try otherSigner.sign("trigger key creation".data(using: .utf8)!)
        let wrongKey = otherSigner.publicKeyData

        XCTAssertFalse(MessageSigner.verify(signature: signature, data: data, publicKey: wrongKey))
        otherSigner.deleteKey()
    }

    func testVerifyRejectsGarbageSignature() {
        let data = "Test".data(using: .utf8)!
        let garbage = Data(repeating: 0xFF, count: 64)
        let publicKey = signer.publicKeyData

        XCTAssertFalse(MessageSigner.verify(signature: garbage, data: data, publicKey: publicKey))
    }

    func testPublicKeyPersistsAcrossInstances() throws {
        let _ = try signer.sign("init key".data(using: .utf8)!)
        let key1 = signer.publicKeyData

        let signer2 = MessageSigner()
        let key2 = signer2.publicKeyData

        XCTAssertEqual(key1, key2)
    }

    func testDeleteKeyCreatesNewKeyOnNextUse() throws {
        let _ = try signer.sign("init key".data(using: .utf8)!)
        let key1 = signer.publicKeyData

        signer.deleteKey()
        let _ = try signer.sign("new key".data(using: .utf8)!)
        let key2 = signer.publicKeyData

        XCTAssertNotEqual(key1, key2)
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild test -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FestivAirTests/MessageSignerTests 2>&1 | grep -E '(Test Case|Tests|BUILD|error:)'`

Expected: All tests pass (using CryptoKit fallback on Simulator since Secure Enclave isn't available)

- [ ] **Step 4: Commit**

```bash
git add Services/MessageSigner.swift Tests/MessageSignerTests.swift
git commit -m "feat: add MessageSigner with Secure Enclave P-256 signing and Simulator fallback"
```

---

## Task 4: KeychainHelper Updates & PII Migration

**Files:**
- Modify: `Utilities/KeychainHelper.swift`
- Modify: `App/FestivAirApp.swift`

- [ ] **Step 1: Update KeychainHelper with new keys and secure accessibility**

In `Utilities/KeychainHelper.swift`, update the `Key` enum and change accessibility:

```swift
// Replace the Key enum (lines 9-15) with:
enum Key: String {
    case userId
    case displayName
    case emoji
    case appleUserIdentifier
    case appleEmail
    // V2 additions
    case squadSecret        // 256-bit AES key for current squad
    case currentSquadId     // Squad ID (moved from UserDefaults)
    case currentJoinCode    // Join code (moved from UserDefaults)
}
```

Change the accessibility level in the `save` method. Replace `kSecAttrAccessibleAfterFirstUnlock` (line ~30) with:

```swift
kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

Delete the entire `restoreToUserDefaults()` method (lines ~100-127).

- [ ] **Step 2: Add Data save/load methods for squad secret**

Add to `KeychainHelper.swift` after the existing `load` method:

```swift
// MARK: - Data Storage (for squad secret)

static func saveData(_ data: Data, for key: Key) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key.rawValue
    ]
    SecItemDelete(query as CFDictionary)

    let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key.rawValue,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    SecItemAdd(addQuery as CFDictionary, nil)
}

static func loadData(for key: Key) -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key.rawValue,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
}
```

- [ ] **Step 3: Update FestivAirApp.swift to remove UserDefaults dependency for identity**

In `App/FestivAirApp.swift`, replace the userId creation block (lines ~96-109) with:

```swift
// Migrate from UserDefaults to Keychain if needed
KeychainHelper.migrateFromUserDefaultsIfNeeded()
// DO NOT call restoreToUserDefaults() — removed in V2

// Load identity from Keychain (authoritative source)
let userId: String
if let stored = KeychainHelper.load(for: .userId) {
    userId = stored
} else {
    userId = UUID().uuidString
    KeychainHelper.save(userId, for: .userId)
}
```

Remove the line `KeychainHelper.restoreToUserDefaults()` (around line 99).

- [ ] **Step 4: Build to verify**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Utilities/KeychainHelper.swift App/FestivAirApp.swift
git commit -m "feat: migrate PII to Keychain, add squad secret storage, remove restoreToUserDefaults"
```

---

## Task 5: Squad Secret Generation & Encryption Rewrite

**Files:**
- Modify: `Services/MeshRelayService.swift`
- Create: `Tests/SquadSecretTests.swift`

- [ ] **Step 1: Write tests for squad secret encryption**

Create `Tests/SquadSecretTests.swift`:

```swift
import XCTest
import CryptoKit
@testable import FestivAir

final class SquadSecretTests: XCTestCase {

    func testGenerateSquadSecretIs32Bytes() {
        let secret = SquadCrypto.generateSecret()
        XCTAssertEqual(secret.count, 32) // 256 bits
    }

    func testEncryptDecryptRoundTrip() throws {
        let secret = SquadCrypto.generateSecret()
        let plaintext = "Hello squad!".data(using: .utf8)!

        let encrypted = try SquadCrypto.encrypt(plaintext, with: secret)
        let decrypted = try SquadCrypto.decrypt(encrypted, with: secret)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testDecryptFailsWithWrongKey() throws {
        let secret1 = SquadCrypto.generateSecret()
        let secret2 = SquadCrypto.generateSecret()
        let plaintext = "Secret message".data(using: .utf8)!

        let encrypted = try SquadCrypto.encrypt(plaintext, with: secret1)

        XCTAssertThrowsError(try SquadCrypto.decrypt(encrypted, with: secret2))
    }

    func testDecryptFailsWithTamperedData() throws {
        let secret = SquadCrypto.generateSecret()
        let plaintext = "Original".data(using: .utf8)!

        var encrypted = try SquadCrypto.encrypt(plaintext, with: secret)
        // Tamper with the last byte
        encrypted[encrypted.count - 1] ^= 0xFF

        XCTAssertThrowsError(try SquadCrypto.decrypt(encrypted, with: secret))
    }

    func testDifferentEncryptionsProduceDifferentCiphertext() throws {
        let secret = SquadCrypto.generateSecret()
        let plaintext = "Same message".data(using: .utf8)!

        let encrypted1 = try SquadCrypto.encrypt(plaintext, with: secret)
        let encrypted2 = try SquadCrypto.encrypt(plaintext, with: secret)

        // AES-GCM uses random nonces, so ciphertext differs even for same plaintext
        XCTAssertNotEqual(encrypted1, encrypted2)
    }

    func testSaveAndLoadSecretFromKeychain() {
        let secret = SquadCrypto.generateSecret()
        KeychainHelper.saveData(secret, for: .squadSecret)

        let loaded = KeychainHelper.loadData(for: .squadSecret)
        XCTAssertEqual(loaded, secret)

        // Cleanup
        KeychainHelper.delete(for: .squadSecret)
    }
}
```

- [ ] **Step 2: Run tests — they should fail (SquadCrypto doesn't exist yet)**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild test -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FestivAirTests/SquadSecretTests 2>&1 | grep -E '(error:|BUILD)'`

Expected: FAIL — `SquadCrypto` not defined

- [ ] **Step 3: Add SquadCrypto to MeshRelayService.swift**

Replace the existing `getSquadKey()`, `encrypt()`, and `decrypt()` methods (lines ~182-218) in `Services/MeshRelayService.swift` with:

```swift
// MARK: - Squad Crypto (V2)

enum SquadCrypto {
    /// Generates a random 256-bit squad secret.
    static func generateSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes)
    }

    /// Encrypts data using AES-GCM with the squad secret.
    static func encrypt(_ data: Data, with secret: Data) throws -> Data {
        let key = SymmetricKey(data: secret)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    /// Decrypts data using AES-GCM with the squad secret.
    static func decrypt(_ data: Data, with secret: Data) throws -> Data {
        let key = SymmetricKey(data: secret)
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    /// Loads the current squad secret from Keychain.
    static func currentSecret() -> Data? {
        KeychainHelper.loadData(for: .squadSecret)
    }

    /// Saves a squad secret to Keychain.
    static func saveSecret(_ secret: Data) {
        KeychainHelper.saveData(secret, for: .squadSecret)
    }

    /// Removes the squad secret (on squad leave).
    static func clearSecret() {
        KeychainHelper.delete(for: .squadSecret)
    }

    enum CryptoError: Error {
        case encryptionFailed
        case noSquadSecret
    }
}
```

Keep the old `getSquadKey()` method temporarily with a deprecation comment for V1 backward compat — it will be removed when Phase 2 completes the migration:

```swift
// MARK: - Legacy V1 Encryption (deprecated — remove after V2 migration)

@available(*, deprecated, message: "Use SquadCrypto instead")
func getSquadKey(_ squadId: String) -> SymmetricKey {
    let keyData = SHA256.hash(data: Data(squadId.utf8))
    return SymmetricKey(data: Data(keyData))
}
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild test -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FestivAirTests/SquadSecretTests 2>&1 | grep -E '(Test Case|Tests|BUILD|error:)'`

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Services/MeshRelayService.swift Tests/SquadSecretTests.swift
git commit -m "feat: add SquadCrypto with random 256-bit secrets, deprecate SHA256 key derivation"
```

---

## Task 6: MeshNetworkManager — Dedup Fix & Direct Messaging

**Files:**
- Modify: `Services/MeshNetworkManager.swift`

- [ ] **Step 1: Replace seenMessageIds Array with Set**

In `Services/MeshNetworkManager.swift`, replace the dedup data structures (around lines 41-43):

```swift
// Replace:
//   private var seenMessageIds: [UUID] = []
//   private let seenMessageIdLimit = 1000
// With:
private var seenMessageIds: Set<UUID> = []
private var seenMessageTimestamps: [UUID: Date] = [:]
private let seenMessageMaxAge: TimeInterval = 300  // 5 minutes
```

- [ ] **Step 2: Update the dedup check in MCSession delegate**

Replace the dedup logic in `session(_:didReceive:fromPeer:)` (around lines 251-270):

```swift
// Replace array-based dedup with Set + timestamp expiration:

// Extract messageId from data
guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let messageIdString = json["messageId"] as? String,
      let messageId = UUID(uuidString: messageIdString) else {
    #if DEBUG
    print("[Mesh] Invalid message format — dropped")
    #endif
    return
}

// Time-based dedup (not count-based)
cleanExpiredMessageIds()
guard !seenMessageIds.contains(messageId) else { return }
seenMessageIds.insert(messageId)
seenMessageTimestamps[messageId] = Date()
```

Add the cleanup method:

```swift
private func cleanExpiredMessageIds() {
    let cutoff = Date().addingTimeInterval(-seenMessageMaxAge)
    let expired = seenMessageTimestamps.filter { $0.value < cutoff }.map { $0.key }
    for id in expired {
        seenMessageIds.remove(id)
        seenMessageTimestamps.removeValue(forKey: id)
    }
}
```

- [ ] **Step 3: Add direct messaging method**

Add to `MeshNetworkManager.swift`:

```swift
// MARK: - Direct Messaging (V2)

/// Sends data to a specific peer by ID, not broadcast.
func sendDirect(_ data: Data, to peerId: MCPeerID) {
    guard session.connectedPeers.contains(peerId) else {
        #if DEBUG
        print("[Mesh] Cannot send direct — peer \(peerId.displayName) not connected")
        #endif
        return
    }
    do {
        try session.send(data, toPeers: [peerId], with: .reliable)
    } catch {
        #if DEBUG
        print("[Mesh] Direct send failed to \(peerId.displayName): \(error)")
        #endif
    }
}

/// Finds a connected MCPeerID by display name.
func peerById(_ displayName: String) -> MCPeerID? {
    session.connectedPeers.first { $0.displayName == displayName }
}
```

- [ ] **Step 4: Build to verify**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Services/MeshNetworkManager.swift
git commit -m "fix: replace dedup Array with Set + timestamp expiration, add direct messaging"
```

---

## Task 7: CloudKit — Join Code Uniqueness & Squad Tier

**Files:**
- Modify: `Services/CloudKitService.swift`
- Modify: `Models/Squad.swift`

- [ ] **Step 1: Update Squad.generateJoinCode() to 8 characters**

In `Models/Squad.swift`, replace `generateJoinCode()` (lines 30-33):

```swift
static func generateJoinCode() -> String {
    let characters = Array(Constants.Squad.codeCharacters)
    return String((0..<Constants.Squad.codeLength).compactMap { _ in characters.randomElement() })
}
```

This now uses `Constants.Squad.codeLength` (8) instead of hardcoded 6.

- [ ] **Step 2: Add join code uniqueness check to CloudKitService**

In `Services/CloudKitService.swift`, add a uniqueness check method and update `createSquad()`:

```swift
// Add new method:
func isJoinCodeUnique(_ code: String) async throws -> Bool {
    let predicate = NSPredicate(format: "joinCode == %@", code)
    let query = CKQuery(recordType: RecordType.squad, predicate: predicate)
    let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 1)
    return results.isEmpty
}

// Add helper to generate unique code:
func generateUniqueJoinCode() async throws -> String {
    for _ in 0..<10 {  // Max 10 attempts
        let code = Squad.generateJoinCode()
        if try await isJoinCodeUnique(code) {
            return code
        }
    }
    // Extremely unlikely with 8-char codes (34^8 = ~1.7 trillion combinations)
    throw CKError(.serverRejectedRequest)
}
```

Update `createSquad()` to use unique code and add tier field:

```swift
// In createSquad(), after creating the CKRecord, add:
record["squadTier"] = "free"  // Default tier
record["tierExpires"] = nil as CKRecordValue?
```

- [ ] **Step 3: Add join attempt rate limiting**

In `CloudKitService.swift`, add rate limiting state:

```swift
// Add properties:
private var joinAttemptTimestamps: [Date] = []

func canAttemptJoin() -> Bool {
    let cutoff = Date().addingTimeInterval(-Constants.Squad.joinAttemptRateWindow)
    joinAttemptTimestamps.removeAll { $0 < cutoff }
    return joinAttemptTimestamps.count < Constants.Squad.joinAttemptRateLimit
}

func recordJoinAttempt() {
    joinAttemptTimestamps.append(Date())
}
```

- [ ] **Step 4: Update AppDelegate URL scheme for 8-char codes**

In `App/AppDelegate.swift`, update the URL handler validation (around line 135). Replace the length check:

```swift
// Replace: guard joinCode.count == 6
guard joinCode.count == Constants.Squad.codeLength
```

Also fix the force casts (lines 57-58):

```swift
// Replace:
//   self.handleMeshSyncTask(task as! BGProcessingTask)
// With:
guard let processingTask = task as? BGProcessingTask else { return }
self.handleMeshSyncTask(processingTask)

// Replace:
//   self.handleLocationUpdateTask(task as! BGAppRefreshTask)
// With:
guard let refreshTask = task as? BGAppRefreshTask else { return }
self.handleLocationUpdateTask(refreshTask)
```

- [ ] **Step 5: Build to verify**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Services/CloudKitService.swift Models/Squad.swift App/AppDelegate.swift
git commit -m "feat: 8-char unique join codes, squad tier field, join rate limiting, fix force casts"
```

---

## Task 8: Wrap Debug Logging

**Files:**
- Modify: Multiple service files

- [ ] **Step 1: Wrap all print statements in DEBUG guards**

Search and replace all `print("[` patterns across service files with `#if DEBUG` guards. The key files:

In each of these files, wrap every `print(` call:

```swift
// Replace patterns like:
//   print("[Mesh] Something happened")
// With:
#if DEBUG
print("[Mesh] Something happened")
#endif
```

Files to update:
- `Services/MeshNetworkManager.swift`
- `Services/MeshRelayService.swift`
- `Services/MeshCoordinator.swift`
- `Services/HavenTransportService.swift`
- `Services/LocationManager.swift`
- `Services/GatewayManager.swift`
- `Services/CloudKitService.swift`
- `Services/PeerTracker.swift`

**Critical:** In all debug logging, redact join codes and user IDs:

```swift
// Replace:
//   print("[Haven] Sent initial heartbeat (joinCode: \(joinCode ?? "none"))")
// With:
#if DEBUG
print("[Haven] Sent initial heartbeat")
#endif
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Services/ App/
git commit -m "fix: wrap debug logging in #if DEBUG, redact sensitive data from logs"
```

---

## Task 9: Integration Smoke Test

**Files:**
- All modified files from Tasks 1-8

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild test -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E '(Test Case|Tests|BUILD|FAIL|error:)'`

Expected: All tests pass

- [ ] **Step 2: Build release configuration**

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Release build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED (verify no debug-only code leaks into release)

- [ ] **Step 3: Verify V2 protocol encode/decode round trip with signing**

This is a manual integration check — run the full test suite one more time and verify no warnings:

Run: `cd /Users/davidjackson/Projects/FestivAir && xcodebuild test -scheme FestivAir -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -c 'warning:'`

Expected: 0 new warnings (some pre-existing warnings from V1 code are acceptable)

- [ ] **Step 4: Final commit for Phase 1**

```bash
git add -A
git commit -m "phase 1 complete: Protocol V2, security foundation, PII migration, 8-char join codes"
```

---

## Phase 1 Completion Checklist

After all tasks are done, verify:

- [ ] `MeshProtocolV2.swift` defines all 13 V2 message types with Codable payloads
- [ ] `V2Envelope` validates version, TTL range (1-10), payload budget, coordinate bounds, text length
- [ ] `MessageSigner` generates P-256 keys (Secure Enclave on device, CryptoKit fallback on Simulator)
- [ ] Sign/verify round trip works; tampered data rejected; wrong key rejected
- [ ] `SquadCrypto` generates random 256-bit secrets (not derived from squad ID)
- [ ] AES-GCM encrypt/decrypt with random nonces; wrong key fails; tampered data fails
- [ ] `KeychainHelper` uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- [ ] `restoreToUserDefaults()` is deleted
- [ ] `FestivAirApp` loads identity from Keychain, not UserDefaults
- [ ] Join codes are 8 characters with uniqueness validation
- [ ] `seenMessageIds` is a `Set<UUID>` with timestamp-based expiration
- [ ] Direct messaging (`sendDirect`) method exists on `MeshNetworkManager`
- [ ] All `print()` statements wrapped in `#if DEBUG`
- [ ] Force casts in `AppDelegate` replaced with conditional casts
- [ ] All tests pass; release build succeeds
