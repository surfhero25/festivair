import Foundation
@testable import FestivAir

/// Stub signer that returns a fixed signature without touching CryptoKit.
struct StubSigner: MessageSignerProtocol {
    var signature: Data = Data("stub-signature".utf8)
    func sign(_ data: Data) throws -> Data { signature }
}

/// Failing signer for tests that exercise sign-failure paths.
struct FailingSigner: MessageSignerProtocol {
    struct E: Error {}
    func sign(_ data: Data) throws -> Data { throw E() }
}

/// Build a valid V2 envelope with a stub signature for tests that need
/// a complete object without going through the builder.
func makeV2Envelope(
    type: V2MessageType = .presencePulse,
    payload: Data? = nil,
    origin: String = "peer-A",
    target: String? = nil,
    squadId: String = "SQUAD1",
    ttl: Int = 5,
    visited: [String]? = nil,
    signature: Data = Data([0x01, 0x02, 0x03])
) -> V2Envelope {
    let body: Data
    if let payload {
        body = payload
    } else {
        let pulse = V2PresencePulse(userId: origin, battery: 80,
                                    isOnline: true, clusterID: nil,
                                    clusterMembers: nil)
        body = try! JSONEncoder().encode(pulse)
    }
    return V2Envelope(
        version: Constants.ProtocolV2.version,
        messageId: UUID(),
        type: type,
        payload: body,
        originPeerId: origin,
        targetPeerId: target,
        squadId: squadId,
        timestamp: Date(),
        ttl: ttl,
        visitedPeers: visited ?? [origin],
        signature: signature
    )
}
