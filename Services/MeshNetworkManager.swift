import Foundation
import MultipeerConnectivity
import Combine

/// Manages peer-to-peer mesh networking via Multipeer Connectivity
final class MeshNetworkManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    @Published private(set) var lastError: Error?

    // MARK: - Configuration
    private let serviceType = "festivair-mesh" // Max 15 chars, lowercase + hyphens
    private let myPeerId: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    // MARK: - Message Handling
    // MeshEnvelope is defined in ChatMessage.swift
    private let messageSubject = PassthroughSubject<(Any, MCPeerID), Never>()
    var messagePublisher: AnyPublisher<(Any, MCPeerID), Never> {
        messageSubject.eraseToAnyPublisher()
    }

    // Track seen messages to prevent duplicates
    private var seenMessageIds = Set<UUID>()
    private let seenMessageIdLimit = 1000

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
        // Restart advertising with new discovery info
        if isAdvertising {
            stopAdvertising()
            startAdvertising()
        }
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
            print("[Mesh] Send error: \(error)")
        }
    }

    // MARK: - Relay Logic

    private func relayEnvelope(_ envelope: MeshEnvelope, excluding sender: MCPeerID) {
        guard let forwarded = envelope.forwarded(by: myPeerId.displayName) else { return }

        let targets = connectedPeers.filter { $0 != sender }
        guard !targets.isEmpty else { return }

        sendEnvelope(forwarded, to: targets)
    }
}

// MARK: - MCSessionDelegate
extension MeshNetworkManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                print("[Mesh] Connected to: \(peerID.displayName)")
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                print("[Mesh] Disconnected from: \(peerID.displayName)")
            case .connecting:
                print("[Mesh] Connecting to: \(peerID.displayName)")
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
                print("[Mesh] Invalid message format")
                return
            }

            // Deduplicate
            guard !seenMessageIds.contains(messageId) else { return }
            seenMessageIds.insert(messageId)

            // Prune old message IDs
            if seenMessageIds.count > seenMessageIdLimit {
                seenMessageIds.removeFirst()
            }

            let envelope = try JSONDecoder().decode(MeshEnvelope.self, from: data)

            // Emit to subscribers
            DispatchQueue.main.async {
                self.messageSubject.send((envelope, peerID))
            }

            // Relay to other peers
            self.relayEnvelope(envelope, excluding: peerID)

        } catch {
            print("[Mesh] Decode error: \(error)")
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
        // Only accept invitations from peers in the same squad
        guard let squadId = squadId else {
            // No squad configured, reject all invitations
            print("[Mesh] Rejecting invitation - no squad configured")
            invitationHandler(false, nil)
            return
        }

        if let context = context,
           let info = try? JSONDecoder().decode([String: String].self, from: context),
           info["squad"] == squadId {
            print("[Mesh] Accepting invitation from squad member: \(peerID.displayName)")
            invitationHandler(true, session)
        } else {
            // Reject peers from different squads or without squad info
            print("[Mesh] Rejecting invitation from non-squad peer: \(peerID.displayName)")
            invitationHandler(false, nil)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.lastError = error
            self.isAdvertising = false
        }
        print("[Mesh] Advertising error: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MeshNetworkManager: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Only invite peers from the same squad
        guard let squadId = squadId else {
            print("[Mesh] Ignoring peer - no squad configured")
            return
        }

        // Check if peer is in same squad
        if let peerSquad = info?["squad"], peerSquad == squadId {
            let context = try? JSONEncoder().encode(discoveryInfo ?? [:])
            browser.invitePeer(peerID, to: session, withContext: context, timeout: 30)
            print("[Mesh] Inviting squad member: \(peerID.displayName)")
        } else {
            print("[Mesh] Ignoring peer from different squad: \(peerID.displayName)")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[Mesh] Lost peer: \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.lastError = error
            self.isBrowsing = false
        }
        print("[Mesh] Browsing error: \(error)")
    }
}
