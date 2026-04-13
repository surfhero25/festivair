import Foundation
import MultipeerConnectivity
import Combine

/// Manages peer-to-peer mesh networking via Multipeer Connectivity
/// Now supports UNIVERSAL RELAY - connects to all FestivAir users, not just squad members
/// Users automatically relay encrypted messages for other squads (without reading them)
final class MeshNetworkManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    @Published private(set) var lastError: Error?
    @Published private(set) var totalMeshUsers = 0  // Estimate of reachable users

    // MARK: - Configuration
    private let serviceType = "festivair-mesh" // Max 15 chars, lowercase + hyphens
    private let myPeerId: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    // MARK: - Universal Relay
    private var universalRelayEnabled = true  // Connect to all FestivAir users

    // MARK: - Message Handling
    // MeshEnvelope is defined in ChatMessage.swift
    private let messageSubject = PassthroughSubject<(Any, MCPeerID), Never>()
    var messagePublisher: AnyPublisher<(Any, MCPeerID), Never> {
        messageSubject.eraseToAnyPublisher()
    }

    // MARK: - Peer Connection Events
    private let peerConnectedSubject = PassthroughSubject<MCPeerID, Never>()
    /// Publisher that emits when a new peer connects - useful for re-broadcasting status
    var peerConnectedPublisher: AnyPublisher<MCPeerID, Never> {
        peerConnectedSubject.eraseToAnyPublisher()
    }

    // Track seen messages to prevent duplicates (Set + timestamp-based expiration)
    private var seenMessageIds: Set<UUID> = []
    private var seenMessageTimestamps: [UUID: Date] = [:]
    private let seenMessageMaxAge: TimeInterval = 300  // 5 minutes

    // MARK: - User Info
    private var squadId: String?
    private var userId: String?
    private var displayName: String

    // MARK: - Init
    init(displayName: String) {
        self.displayName = displayName
        self.myPeerId = MCPeerID(displayName: displayName)
        super.init()
        setupSession()
    }

    private func setupSession() {
        session = MCSession(
            peer: myPeerId,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(
            peer: myPeerId,
            serviceType: serviceType
        )
        browser.delegate = self
    }

    private var discoveryInfo: [String: String]? {
        var info: [String: String] = [:]
        if let squadId = squadId {
            info["squad"] = squadId
        }
        if let userId = userId {
            info["user"] = userId
        }
        return info.isEmpty ? nil : info
    }

    // MARK: - Public API

    func configure(squadId: String, userId: String) {
        self.squadId = squadId
        self.userId = userId
        #if DEBUG
        print("[Mesh] Configured with squadId: <redacted>, userId: <redacted>")
        #endif

        // CRITICAL: Recreate advertiser and browser with new discoveryInfo
        // MCNearbyServiceAdvertiser captures discoveryInfo at creation time,
        // so we must create new instances when config changes
        let wasAdvertising = isAdvertising
        let wasBrowsing = isBrowsing

        if isAdvertising {
            stopAdvertising()
        }
        if isBrowsing {
            stopBrowsing()
        }

        // Recreate with updated discoveryInfo
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(
            peer: myPeerId,
            serviceType: serviceType
        )
        browser.delegate = self

        // Restart if they were running
        if wasAdvertising {
            startAdvertising()
        }
        if wasBrowsing {
            startBrowsing()
        }

        #if DEBUG
        print("[Mesh] Recreated advertiser/browser with updated discoveryInfo")
        #endif
    }

    func startAdvertising() {
        guard !isAdvertising else { return }
        advertiser.startAdvertisingPeer()
        isAdvertising = true
    }

    func stopAdvertising() {
        advertiser.stopAdvertisingPeer()
        isAdvertising = false
    }

    func startBrowsing() {
        guard !isBrowsing else { return }
        browser.startBrowsingForPeers()
        isBrowsing = true
    }

    func stopBrowsing() {
        browser.stopBrowsingForPeers()
        isBrowsing = false
    }

    func startAll() {
        startAdvertising()
        startBrowsing()
    }

    func stopAll() {
        stopAdvertising()
        stopBrowsing()
        session.disconnect()
        connectedPeers = []
    }

    // MARK: - Sending Messages

    func broadcast(_ message: MeshMessagePayload) {
        // Validate userId is present and not empty for messages that require it
        if let userId = message.userId, userId.isEmpty {
            #if DEBUG
            print("[Mesh] Warning: Attempting to broadcast with empty userId")
            #endif
            return
        }
        let envelope = MeshEnvelope(message: message, originPeerId: myPeerId.displayName)
        sendEnvelope(envelope, to: connectedPeers)
    }

    func send(_ message: MeshMessagePayload, to peer: MCPeerID) {
        let envelope = MeshEnvelope(message: message, originPeerId: myPeerId.displayName)
        sendEnvelope(envelope, to: [peer])
    }

    private func sendEnvelope(_ envelope: MeshEnvelope, to peers: [MCPeerID]) {
        guard !peers.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(envelope)
            try session.send(data, toPeers: peers, with: .reliable)
        } catch {
            lastError = error
            #if DEBUG
            print("[Mesh] Send error: \(error)")
            #endif
        }
    }

    // MARK: - Relay Logic

    /// UNIVERSAL RELAY: Forward messages to all connected peers
    /// This enables the festival-wide mesh - users relay for ALL squads
    private func relayEnvelope(_ envelope: MeshEnvelope, excluding sender: MCPeerID) {
        // Check TTL before relaying - forwarded() returns nil if TTL exceeded
        guard let forwarded = envelope.forwarded(by: myPeerId.displayName) else {
            #if DEBUG
            print("[Mesh] Not relaying - TTL exceeded or already forwarded")
            #endif
            return
        }

        let targets = connectedPeers.filter { $0 != sender }
        guard !targets.isEmpty else { return }

        // Relay to ALL connected peers - not just squad members
        // The message is encrypted, so non-squad members can't read it
        // They just help it reach its destination
        sendEnvelope(forwarded, to: targets)
    }

    /// Check if a message should be processed locally
    private func shouldProcessLocally(_ envelope: MeshEnvelope) -> Bool {
        // Process if it's for our squad or if it's a broadcast
        return envelope.isForMySquad
    }

    private func cleanExpiredMessageIds() {
        let cutoff = Date().addingTimeInterval(-seenMessageMaxAge)
        let expired = seenMessageTimestamps.filter { $0.value < cutoff }.map { $0.key }
        for id in expired {
            seenMessageIds.remove(id)
            seenMessageTimestamps.removeValue(forKey: id)
        }
    }

    // MARK: - Raw Data (V2)

    /// Broadcasts raw data to all connected peers (for V2 pre-encoded envelopes)
    func broadcastRaw(_ data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            #if DEBUG
            print("[Mesh] Raw broadcast failed: \(error)")
            #endif
        }
    }

    // MARK: - Direct Messaging (V2)

    /// Sends data to a specific peer, not broadcast.
    func sendDirect(_ data: Data, to peerId: MCPeerID) {
        guard session.connectedPeers.contains(peerId) else {
            #if DEBUG
            print("[Mesh] Cannot send direct — peer not connected")
            #endif
            return
        }
        do {
            try session.send(data, toPeers: [peerId], with: .reliable)
        } catch {
            #if DEBUG
            print("[Mesh] Direct send failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Finds a connected MCPeerID by display name.
    func peerById(_ displayName: String) -> MCPeerID? {
        session.connectedPeers.first { $0.displayName == displayName }
    }
}

// MARK: - MCSessionDelegate
extension MeshNetworkManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                let isNewPeer = !self.connectedPeers.contains(peerID)
                if isNewPeer {
                    self.connectedPeers.append(peerID)
                    // Notify subscribers about new peer (for re-broadcasting status, etc.)
                    self.peerConnectedSubject.send(peerID)
                }
                #if DEBUG
                print("[Mesh] Connected to: \(peerID.displayName)")
                #endif
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                #if DEBUG
                print("[Mesh] Disconnected from: \(peerID.displayName)")
                #endif
            case .connecting:
                #if DEBUG
                print("[Mesh] Connecting to: \(peerID.displayName)")
                #endif
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            // Decode as generic dictionary first, then as MeshEnvelope
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messageIdString = json["messageId"] as? String,
                  let messageId = UUID(uuidString: messageIdString) else {
                #if DEBUG
                print("[Mesh] Invalid message format")
                #endif
                return
            }

            // Time-based dedup
            cleanExpiredMessageIds()
            guard !seenMessageIds.contains(messageId) else { return }
            seenMessageIds.insert(messageId)
            seenMessageTimestamps[messageId] = Date()

            let envelope = try JSONDecoder().decode(MeshEnvelope.self, from: data)

            // Emit to subscribers
            DispatchQueue.main.async {
                self.messageSubject.send((envelope, peerID))
            }

            // Relay to other peers
            self.relayEnvelope(envelope, excluding: peerID)

        } catch {
            #if DEBUG
            print("[Mesh] Decode error: \(error)")
            #endif
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MeshNetworkManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // UNIVERSAL RELAY: Accept ALL FestivAir users
        // This builds a mesh across the entire festival, not just squads
        // Messages are encrypted per-squad so other users can't read them

        if universalRelayEnabled {
            // Accept anyone running FestivAir
            #if DEBUG
            print("[Mesh] Accepting invitation (universal relay): \(peerID.displayName)")
            #endif
            invitationHandler(true, session)
            return
        }

        // Fallback: squad-only mode (if universal relay disabled)
        guard let squadId = squadId else {
            #if DEBUG
            print("[Mesh] Rejecting invitation - no squad configured")
            #endif
            invitationHandler(false, nil)
            return
        }

        if let context = context,
           let info = try? JSONDecoder().decode([String: String].self, from: context),
           info["squad"] == squadId {
            #if DEBUG
            print("[Mesh] Accepting invitation from squad member: \(peerID.displayName)")
            #endif
            invitationHandler(true, session)
        } else {
            #if DEBUG
            print("[Mesh] Rejecting invitation from non-squad peer: \(peerID.displayName)")
            #endif
            invitationHandler(false, nil)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.lastError = error
            self.isAdvertising = false
        }
        #if DEBUG
        print("[Mesh] Advertising error: \(error)")
        #endif
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MeshNetworkManager: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // UNIVERSAL RELAY: Invite ALL FestivAir users
        // This creates a festival-wide mesh where everyone helps relay

        if universalRelayEnabled {
            // Invite anyone running FestivAir
            let context = try? JSONEncoder().encode(discoveryInfo ?? [:])
            browser.invitePeer(peerID, to: session, withContext: context, timeout: 30)
            #if DEBUG
            print("[Mesh] Inviting peer (universal relay): \(peerID.displayName)")
            #endif
            return
        }

        // Fallback: squad-only mode
        guard let squadId = squadId else {
            #if DEBUG
            print("[Mesh] Ignoring peer - no squad configured")
            #endif
            return
        }

        if let peerSquad = info?["squad"], peerSquad == squadId {
            let context = try? JSONEncoder().encode(discoveryInfo ?? [:])
            browser.invitePeer(peerID, to: session, withContext: context, timeout: 30)
            #if DEBUG
            print("[Mesh] Inviting squad member: \(peerID.displayName)")
            #endif
        } else {
            #if DEBUG
            print("[Mesh] Ignoring peer from different squad: \(peerID.displayName)")
            #endif
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        #if DEBUG
        print("[Mesh] Lost peer: \(peerID.displayName)")
        #endif
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.lastError = error
            self.isBrowsing = false
        }
        #if DEBUG
        print("[Mesh] Browsing error: \(error)")
        #endif
    }
}
