import Foundation
import Network
import Combine

/// TCP transport that discovers and connects to a Haven relay server
/// (Raspberry Pi running an asyncio TCP server) via Bonjour.
///
/// Wire protocol: 4-byte big-endian length prefix + JSON payload.
/// On connect, sends a heartbeat with joinCode so the server knows our squad.
/// Auto-reconnects on disconnect with exponential backoff.
final class HavenTransportService: MeshTransport {

    // MARK: - MeshTransport Conformance

    var messagePublisher: AnyPublisher<MeshEnvelope, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    private(set) var isConnected: Bool = false

    // MARK: - Private State

    private let messageSubject = PassthroughSubject<MeshEnvelope, Never>()
    private let queue = DispatchQueue(label: "com.festivair.haven-transport", qos: .userInitiated)

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isStarted = false

    /// Buffer for incoming TCP stream data (handles partial frames)
    private var receiveBuffer = Data()

    // MARK: - Reconnect Backoff

    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 30
    private var reconnectWorkItem: DispatchWorkItem?

    // MARK: - Bonjour

    private let bonjourType = "_festivair-haven._tcp"

    // MARK: - Resolved Endpoint (for reconnect)

    private var discoveredEndpoint: NWEndpoint?

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true
            self.startBrowsing()
            print("[Haven] Transport started - browsing for \(self.bonjourType)")
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStarted = false
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.stopBrowsing()
            self.disconnect()
            print("[Haven] Transport stopped")
        }
    }

    func broadcast(_ message: MeshMessagePayload) {
        queue.async { [weak self] in
            guard let self, self.isConnected else { return }

            let displayName = UserDefaults.standard.string(forKey: "FestivAir.DisplayName") ?? "Festival Fan"
            let envelope = MeshEnvelope(message: message, originPeerId: displayName)
            self.sendEnvelope(envelope)
        }
    }

    // MARK: - Bonjour Browsing

    private func startBrowsing() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: bonjourType, domain: nil)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[Haven] Browser ready")
            case .failed(let error):
                print("[Haven] Browser failed: \(error)")
                self?.restartBrowsingAfterDelay()
            case .cancelled:
                print("[Haven] Browser cancelled")
            default:
                break
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }

            for change in changes {
                switch change {
                case .added(let result):
                    print("[Haven] Discovered relay server: \(result.endpoint)")
                    self.discoveredEndpoint = result.endpoint
                    self.connectToEndpoint(result.endpoint)

                case .removed(let result):
                    print("[Haven] Lost relay server: \(result.endpoint)")
                    if case .service = result.endpoint {
                        // If this was our connected server, the connection state handler
                        // will handle reconnect
                    }

                default:
                    break
                }
            }
        }

        newBrowser.start(queue: queue)
        browser = newBrowser
    }

    private func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func restartBrowsingAfterDelay() {
        guard isStarted else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isStarted else { return }
            self.startBrowsing()
        }
        queue.asyncAfter(deadline: .now() + 5, execute: item)
    }

    // MARK: - TCP Connection

    private func connectToEndpoint(_ endpoint: NWEndpoint) {
        // Don't connect if we already have an active connection
        guard connection == nil || !isConnected else {
            print("[Haven] Already connected, ignoring new endpoint")
            return
        }

        disconnect()

        let parameters = NWParameters.tcp
        let newConnection = NWConnection(to: endpoint, using: parameters)

        newConnection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("[Haven] Connected to relay server")
                self.isConnected = true
                self.reconnectAttempt = 0
                self.receiveBuffer = Data()
                self.sendInitialHeartbeat()
                self.startReceiveLoop()

            case .failed(let error):
                print("[Haven] Connection failed: \(error)")
                self.isConnected = false
                self.connection = nil
                self.scheduleReconnect()

            case .cancelled:
                print("[Haven] Connection cancelled")
                self.isConnected = false
                self.connection = nil

            case .waiting(let error):
                print("[Haven] Connection waiting: \(error)")

            default:
                break
            }
        }

        newConnection.start(queue: queue)
        connection = newConnection
    }

    private func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        receiveBuffer = Data()
    }

    // MARK: - Reconnect with Backoff

    private func scheduleReconnect() {
        guard isStarted else { return }

        reconnectWorkItem?.cancel()

        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1

        print("[Haven] Reconnecting in \(delay)s (attempt \(reconnectAttempt))")

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isStarted else { return }
            if let endpoint = self.discoveredEndpoint {
                self.connectToEndpoint(endpoint)
            } else {
                // No cached endpoint; restart browsing
                self.stopBrowsing()
                self.startBrowsing()
            }
        }
        reconnectWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Initial Heartbeat

    /// On connect, send a heartbeat with our joinCode so the server can route messages
    private func sendInitialHeartbeat() {
        let userId = UserDefaults.standard.string(forKey: "FestivAir.UserId") ?? ""
        let displayName = UserDefaults.standard.string(forKey: "FestivAir.DisplayName") ?? "Festival Fan"
        let emoji = UserDefaults.standard.string(forKey: "FestivAir.Emoji") ?? "\u{1F3A7}"
        let joinCode = UserDefaults.standard.string(forKey: "FestivAir.CurrentJoinCode")

        let heartbeat = MeshMessagePayload.heartbeat(
            userId: userId,
            displayName: displayName,
            emoji: emoji,
            batteryLevel: 100,
            hasService: false,
            location: nil,
            joinCode: joinCode
        )

        let envelope = MeshEnvelope(message: heartbeat, originPeerId: displayName)
        sendEnvelope(envelope)
        print("[Haven] Sent initial heartbeat (joinCode: \(joinCode ?? "none"))")
    }

    // MARK: - Send (Length-Prefixed JSON)

    private func sendEnvelope(_ envelope: MeshEnvelope) {
        guard let conn = connection, isConnected else { return }

        do {
            let jsonData = try JSONEncoder().encode(envelope)

            // Build frame: 4-byte big-endian length + JSON payload
            var length = UInt32(jsonData.count).bigEndian
            var frame = Data(bytes: &length, count: 4)
            frame.append(jsonData)

            conn.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    print("[Haven] Send error: \(error)")
                }
            })
        } catch {
            print("[Haven] Encode error: \(error)")
        }
    }

    // MARK: - Receive Loop (Length-Prefixed Framing)

    private func startReceiveLoop() {
        guard let conn = connection, isConnected else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let data = content, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processFrames()
            }

            if isComplete {
                print("[Haven] Connection closed by server")
                self.isConnected = false
                self.connection = nil
                self.scheduleReconnect()
                return
            }

            if let error {
                print("[Haven] Receive error: \(error)")
                self.isConnected = false
                self.connection?.cancel()
                self.connection = nil
                self.scheduleReconnect()
                return
            }

            // Continue receiving
            self.startReceiveLoop()
        }
    }

    /// Extract complete frames from the receive buffer and decode them
    private func processFrames() {
        while receiveBuffer.count >= 4 {
            // Read 4-byte big-endian length prefix
            let lengthBytes = receiveBuffer.prefix(4)
            let length = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            let frameSize = 4 + Int(length)

            // Wait for complete frame
            guard receiveBuffer.count >= frameSize else { return }

            // Extract JSON payload
            let jsonData = receiveBuffer.subdata(in: 4..<frameSize)
            receiveBuffer.removeFirst(frameSize)

            // Decode and publish
            do {
                let envelope = try JSONDecoder().decode(MeshEnvelope.self, from: jsonData)
                messageSubject.send(envelope)
            } catch {
                print("[Haven] Decode error: \(error)")
            }
        }
    }
}
