import Foundation
import Combine
import simd
import MultipeerConnectivity
#if canImport(NearbyInteraction)
import NearbyInteraction
#endif

/// One-to-one UWB precision ranging via Apple's NearbyInteraction framework.
///
/// Used when the user is navigating to a specific squad member who is close enough for U1/U2 ranging.
/// Falls back silently to GPS when:
///   - Either device doesn't have UWB (pre-iPhone 11, or non-Apple device)
///   - Peers go out of UWB range (~9 m indoor / ~30 m outdoor line-of-sight)
///   - Session fails or is interrupted
///
/// Architecture:
///   - Each phone keeps one NISession per actively-ranged peer.
///   - `NIDiscoveryToken` is exchanged out-of-band over MultipeerConnectivity using a small
///     custom binary frame (magic prefix `FAUWB!\0\0`).
///   - When both phones have each other's tokens, both call `run(_:)` and observe
///     `session(_:didUpdate:)` for distance + direction.
@MainActor
final class UWBPrecisionFinder: NSObject, ObservableObject {

    // MARK: - Public state

    /// Distance to the active target in metres, when UWB is reporting.
    @Published private(set) var distance: Float?

    /// Unit vector toward the active target in the device's local horizon coordinate frame, when reporting.
    /// `nil` means UWB is not currently producing direction (out of range, or device doesn't support direction).
    @Published private(set) var direction: simd_float3?

    /// True while UWB is producing fresh data for the active target.
    @Published private(set) var isPrecisionLocked: Bool = false

    /// Whether this device has a U1/U2 chip and supports NearbyInteraction.
    let isHardwareSupported: Bool

    // MARK: - Private state

    private weak var meshManager: MeshNetworkManager?
    private var inboundSubscription: AnyCancellable?

    /// Maps peer.displayName → live NISession for that peer.
    private var sessions: [String: NSObject] = [:]

    /// Maps peer.displayName → MCPeerID, captured at handshake time.
    private var peerIDs: [String: MCPeerID] = [:]

    /// Display name of the peer currently selected as the navigation target.
    /// Direction/distance Published values mirror this peer's session.
    private var activeTargetDisplayName: String?

    /// Magic frame prefix that identifies UWB-control bytes on the mesh side.
    static let framePrefix: [UInt8] = Array("FAUWB!\0\0".utf8)

    private enum FrameKind: UInt8 {
        case tokenRequest  = 1   // "I want to range with you, here is my token"
        case tokenResponse = 2   // "Acknowledged, here is my token"
        case stop          = 3   // "Tearing down, please invalidate your session"
    }

    // MARK: - Init

    override init() {
        if #available(iOS 14.0, *) {
            #if canImport(NearbyInteraction)
            self.isHardwareSupported = NISession.isSupported
            #else
            self.isHardwareSupported = false
            #endif
        } else {
            self.isHardwareSupported = false
        }
        super.init()
    }

    /// Bind the finder to the mesh transport. Idempotent.
    func attach(to mesh: MeshNetworkManager) {
        self.meshManager = mesh
        self.inboundSubscription?.cancel()
        self.inboundSubscription = mesh.uwbInboundPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload, peerID in
                self?.handleInbound(payload: payload, from: peerID)
            }
    }

    // MARK: - Public control

    /// Begin (or refocus) precision ranging toward `peerDisplayName`.
    /// No-op if the local device lacks UWB hardware. The transport must already have a connected MCPeerID matching the name.
    func startRanging(to peerDisplayName: String) {
        guard isHardwareSupported else { return }
        guard let mesh = meshManager else { return }
        guard let peerID = mesh.peerById(peerDisplayName) else { return }

        activeTargetDisplayName = peerDisplayName
        peerIDs[peerDisplayName] = peerID

        // Reset published state so stale values don't bleed across targets.
        distance = nil
        direction = nil
        isPrecisionLocked = false

        if #available(iOS 14.0, *) {
            #if canImport(NearbyInteraction)
            // Reuse existing session for this peer if any, otherwise create new.
            let session = (sessions[peerDisplayName] as? NISession) ?? NISession()
            session.delegate = self
            sessions[peerDisplayName] = session

            guard let token = session.discoveryToken else {
                #if DEBUG
                print("[UWB] No discovery token yet for \(peerDisplayName)")
                #endif
                return
            }
            sendToken(token, kind: .tokenRequest, to: peerID)
            #endif
        }
    }

    /// Stop precision ranging toward `peerDisplayName`. Tears down the local session and tells the peer to do the same.
    func stopRanging(to peerDisplayName: String) {
        if let peerID = peerIDs[peerDisplayName] {
            sendStop(to: peerID)
        }
        invalidateSession(for: peerDisplayName)
        if activeTargetDisplayName == peerDisplayName {
            activeTargetDisplayName = nil
            distance = nil
            direction = nil
            isPrecisionLocked = false
        }
    }

    /// Stop ranging for all current peers. Used during sign-out / app teardown.
    func stopAll() {
        for name in Array(sessions.keys) {
            stopRanging(to: name)
        }
    }

    // MARK: - Inbound mesh handling

    private func handleInbound(payload: Data, from peerID: MCPeerID) {
        guard let kindByte = payload.first, let kind = FrameKind(rawValue: kindByte) else { return }
        let body = payload.dropFirst()

        switch kind {
        case .tokenRequest:
            if #available(iOS 14.0, *) {
                #if canImport(NearbyInteraction)
                guard isHardwareSupported, let token = decodeToken(body) else { return }
                peerIDs[peerID.displayName] = peerID
                let session = (sessions[peerID.displayName] as? NISession) ?? NISession()
                session.delegate = self
                sessions[peerID.displayName] = session
                runSession(session, peerToken: token)
                if let myToken = session.discoveryToken {
                    sendToken(myToken, kind: .tokenResponse, to: peerID)
                }
                #endif
            }

        case .tokenResponse:
            if #available(iOS 14.0, *) {
                #if canImport(NearbyInteraction)
                guard let session = sessions[peerID.displayName] as? NISession,
                      let token = decodeToken(body) else { return }
                runSession(session, peerToken: token)
                #endif
            }

        case .stop:
            invalidateSession(for: peerID.displayName)
            if activeTargetDisplayName == peerID.displayName {
                distance = nil
                direction = nil
                isPrecisionLocked = false
            }
        }
    }

    // MARK: - Session lifecycle helpers

    @available(iOS 14.0, *)
    private func runSession(_ session: NSObject, peerToken: NSObject) {
        #if canImport(NearbyInteraction)
        guard let session = session as? NISession,
              let peerToken = peerToken as? NIDiscoveryToken else { return }
        let config = NINearbyPeerConfiguration(peerToken: peerToken)
        session.run(config)
        #endif
    }

    private func invalidateSession(for displayName: String) {
        if #available(iOS 14.0, *) {
            #if canImport(NearbyInteraction)
            (sessions[displayName] as? NISession)?.invalidate()
            #endif
        }
        sessions.removeValue(forKey: displayName)
        peerIDs.removeValue(forKey: displayName)
    }

    // MARK: - Token wire format (NSKeyedArchiver)

    @available(iOS 14.0, *)
    private func sendToken(_ token: NSObject, kind: FrameKind, to peerID: MCPeerID) {
        #if canImport(NearbyInteraction)
        guard let token = token as? NIDiscoveryToken,
              let body = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        sendFrame(kind: kind, body: body, to: peerID)
        #endif
    }

    private func sendStop(to peerID: MCPeerID) {
        sendFrame(kind: .stop, body: Data(), to: peerID)
    }

    private func sendFrame(kind: FrameKind, body: Data, to peerID: MCPeerID) {
        var frame = Data()
        frame.append(contentsOf: Self.framePrefix)
        frame.append(kind.rawValue)
        frame.append(body)
        meshManager?.sendDirect(frame, to: peerID)
    }

    @available(iOS 14.0, *)
    private func decodeToken(_ data: Data) -> NSObject? {
        #if canImport(NearbyInteraction)
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: Data(data))
        #else
        return nil
        #endif
    }
}

// MARK: - NISessionDelegate

#if canImport(NearbyInteraction)
@available(iOS 14.0, *)
extension UWBPrecisionFinder: NISessionDelegate {

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor in
            self.applyUpdate(session: session, nearbyObjects: nearbyObjects)
        }
    }

    @MainActor
    private func applyUpdate(session: NISession, nearbyObjects: [NINearbyObject]) {
        // Find which peer this session belongs to.
        guard let peerName = sessions.first(where: { ($0.value as? NISession) === session })?.key else { return }
        guard peerName == activeTargetDisplayName else { return }
        guard let object = nearbyObjects.first else {
            isPrecisionLocked = false
            return
        }

        distance = object.distance
        direction = object.direction
        isPrecisionLocked = object.distance != nil
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            // Tear down on permanent removal; on timeout, keep session alive — peer may come back into range.
            switch reason {
            case .peerEnded:
                if let peerName = self.sessions.first(where: { ($0.value as? NISession) === session })?.key {
                    self.invalidateSession(for: peerName)
                    if peerName == self.activeTargetDisplayName {
                        self.distance = nil
                        self.direction = nil
                        self.isPrecisionLocked = false
                    }
                }
            case .timeout:
                self.isPrecisionLocked = false
            @unknown default:
                self.isPrecisionLocked = false
            }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            self.isPrecisionLocked = false
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        // Re-run with the same peer token if we still have one; framework requires a fresh run after suspension.
        Task { @MainActor in
            guard let entry = self.sessions.first(where: { ($0.value as? NISession) === session }),
                  let liveSession = entry.value as? NISession else { return }
            // We don't keep peer tokens around — easiest path is to re-handshake.
            if let peerID = self.peerIDs[entry.key], let myToken = liveSession.discoveryToken {
                self.sendToken(myToken, kind: .tokenRequest, to: peerID)
            }
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            if let peerName = self.sessions.first(where: { ($0.value as? NISession) === session })?.key {
                self.invalidateSession(for: peerName)
                if peerName == self.activeTargetDisplayName {
                    self.distance = nil
                    self.direction = nil
                    self.isPrecisionLocked = false
                }
            }
            #if DEBUG
            print("[UWB] Session invalidated: \(error.localizedDescription)")
            #endif
        }
    }
}
#endif
