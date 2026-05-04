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

    /// Maps peer userId → live NISession for that peer.
    private var sessions: [String: NSObject] = [:]

    /// Maps peer userId → MCPeerID, captured at handshake time.
    private var peerIDs: [String: MCPeerID] = [:]

    /// userId of the peer currently selected as the navigation target.
    /// Direction/distance Published values mirror this peer's session.
    private var activeTargetUserId: String?

    /// Optional gate: when set, only peers whose userId is in `currentSquadMemberIds` may initiate UWB ranging with us.
    /// Set by the host app whenever squad membership changes; nil means "accept any peer" (used in tests).
    var currentSquadMemberIds: Set<String>?

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

    /// Begin (or refocus) precision ranging toward `peerUserId`.
    /// No-op if the local device lacks UWB hardware or the peer isn't currently connected via MPC.
    func startRanging(to peerUserId: String) {
        guard isHardwareSupported else { return }
        guard let mesh = meshManager else { return }
        guard let peerID = mesh.peerById(peerUserId) else { return }

        activeTargetUserId = peerUserId
        peerIDs[peerUserId] = peerID

        // Reset published state so stale values don't bleed across targets.
        distance = nil
        direction = nil
        isPrecisionLocked = false

        if #available(iOS 14.0, *) {
            #if canImport(NearbyInteraction)
            // Reuse existing session for this peer if any, otherwise create new.
            let session = (sessions[peerUserId] as? NISession) ?? NISession()
            session.delegate = self
            sessions[peerUserId] = session

            guard let token = session.discoveryToken else {
                #if DEBUG
                print("[UWB] No discovery token yet for \(peerUserId)")
                #endif
                return
            }
            sendToken(token, kind: .tokenRequest, to: peerID)
            #endif
        }
    }

    /// Stop precision ranging toward `peerUserId`. Tears down the local session and tells the peer to do the same.
    func stopRanging(to peerUserId: String) {
        if let peerID = peerIDs[peerUserId] {
            sendStop(to: peerID)
        }
        invalidateSession(for: peerUserId)
        if activeTargetUserId == peerUserId {
            activeTargetUserId = nil
            distance = nil
            direction = nil
            isPrecisionLocked = false
        }
    }

    /// Stop ranging for all current peers. Used during sign-out / app teardown.
    func stopAll() {
        for userId in Array(sessions.keys) {
            stopRanging(to: userId)
        }
    }

    // MARK: - Inbound mesh handling

    private func handleInbound(payload: Data, from peerID: MCPeerID) {
        guard let kindByte = payload.first, let kind = FrameKind(rawValue: kindByte) else { return }
        // Require a stable userId on the inbound peer; pre-userId-suffix builds are rejected outright.
        guard let peerUserId = peerID.embeddedUserId else {
            #if DEBUG
            print("[UWB] Reject inbound from peer without embedded userId: \(peerID.displayName)")
            #endif
            return
        }
        // Squad-membership gate: if a roster has been published, drop frames from non-members.
        if let allowList = currentSquadMemberIds, !allowList.contains(peerUserId) {
            #if DEBUG
            print("[UWB] Reject inbound from non-squad peer: \(peerUserId)")
            #endif
            return
        }
        let body = payload.dropFirst()

        switch kind {
        case .tokenRequest:
            if #available(iOS 14.0, *) {
                #if canImport(NearbyInteraction)
                guard isHardwareSupported, let token = decodeToken(body) else { return }
                peerIDs[peerUserId] = peerID
                let session = (sessions[peerUserId] as? NISession) ?? NISession()
                session.delegate = self
                sessions[peerUserId] = session
                runSession(session, peerToken: token)
                if let myToken = session.discoveryToken {
                    sendToken(myToken, kind: .tokenResponse, to: peerID)
                }
                #endif
            }

        case .tokenResponse:
            if #available(iOS 14.0, *) {
                #if canImport(NearbyInteraction)
                guard let session = sessions[peerUserId] as? NISession,
                      let token = decodeToken(body) else { return }
                runSession(session, peerToken: token)
                #endif
            }

        case .stop:
            invalidateSession(for: peerUserId)
            if activeTargetUserId == peerUserId {
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
        guard let peerUserId = sessions.first(where: { ($0.value as? NISession) === session })?.key else { return }
        guard peerUserId == activeTargetUserId else { return }
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
                if let peerUserId = self.sessions.first(where: { ($0.value as? NISession) === session })?.key {
                    self.invalidateSession(for: peerUserId)
                    if peerUserId == self.activeTargetUserId {
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
            if let peerUserId = self.sessions.first(where: { ($0.value as? NISession) === session })?.key {
                self.invalidateSession(for: peerUserId)
                if peerUserId == self.activeTargetUserId {
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
