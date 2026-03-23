import Foundation
import Combine

/// Protocol for mesh message transports (MPC, TCP Haven, etc.)
/// Both MultipeerConnectivity and Haven TCP transports conform to this,
/// allowing the coordinator to receive messages from any transport.
protocol MeshTransport: AnyObject {
    /// Publisher that emits decoded MeshEnvelope messages from this transport
    var messagePublisher: AnyPublisher<MeshEnvelope, Never> { get }

    /// Whether the transport is currently connected and able to send/receive
    var isConnected: Bool { get }

    /// Broadcast a message payload to all reachable peers via this transport
    func broadcast(_ message: MeshMessagePayload)

    /// Start the transport (discovery, connection, etc.)
    func start()

    /// Stop the transport and clean up resources
    func stop()
}
