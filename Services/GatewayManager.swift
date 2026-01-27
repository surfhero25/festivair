import Foundation
import CoreTelephony
import Network
import Combine

/// Manages gateway election and cellular signal monitoring
final class GatewayManager: ObservableObject {

    // MARK: - Published State
    @Published private(set) var isGateway = false
    @Published private(set) var gatewayPeerId: String?
    @Published private(set) var signalStrength: Int = 0 // 0-4 bars equivalent
    @Published private(set) var hasInternetAccess = false
    @Published private(set) var batteryLevel: Int = 100

    // MARK: - Configuration
    private let electionInterval: TimeInterval = 30
    private let minBatteryForGateway = 20 // Don't be gateway if below 20%
    private let gatewayRotationBattery = 30 // Rotate if battery drops below 30%

    // MARK: - Private
    private var electionTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var peerSignalStrengths: [String: Int] = [:]
    private var peerBatteryLevels: [String: Int] = [:]
    private let myPeerId: String

    // MARK: - Callbacks
    var onBecomeGateway: (() -> Void)?
    var onResignGateway: (() -> Void)?
    var onGatewayChanged: ((String?) -> Void)?

    // MARK: - Init
    init(peerId: String) {
        self.myPeerId = peerId
        setupNetworkMonitoring()
        setupBatteryMonitoring()
    }

    deinit {
        stopElection()
        pathMonitor?.cancel()
    }

    // MARK: - Public API

    func startElection() {
        electionTimer?.invalidate()
        electionTimer = Timer.scheduledTimer(withTimeInterval: electionInterval, repeats: true) { [weak self] _ in
            self?.performElection()
        }
        // Perform initial election
        performElection()
    }

    func stopElection() {
        electionTimer?.invalidate()
        electionTimer = nil
        resignAsGateway()
    }

    func updatePeerSignalStrength(peerId: String, strength: Int, battery: Int) {
        peerSignalStrengths[peerId] = strength
        peerBatteryLevels[peerId] = battery
    }

    func removePeer(_ peerId: String) {
        peerSignalStrengths.removeValue(forKey: peerId)
        peerBatteryLevels.removeValue(forKey: peerId)

        // If removed peer was gateway, trigger new election
        if gatewayPeerId == peerId {
            performElection()
        }
    }

    // MARK: - Gateway Election

    private func performElection() {
        // Include self in candidates
        var candidates: [(peerId: String, score: Int)] = []

        // My score
        let myScore = calculateGatewayScore(signalStrength: signalStrength, battery: batteryLevel)
        if batteryLevel >= minBatteryForGateway && hasInternetAccess {
            candidates.append((myPeerId, myScore))
        }

        // Peer scores
        for (peerId, strength) in peerSignalStrengths {
            let battery = peerBatteryLevels[peerId] ?? 50
            if battery >= minBatteryForGateway {
                let score = calculateGatewayScore(signalStrength: strength, battery: battery)
                candidates.append((peerId, score))
            }
        }

        // Sort by score (higher is better)
        candidates.sort { $0.score > $1.score }

        // Pick winner
        guard let winner = candidates.first else {
            // No one qualified
            gatewayPeerId = nil
            if isGateway {
                resignAsGateway()
            }
            return
        }

        let previousGateway = gatewayPeerId
        gatewayPeerId = winner.peerId

        if winner.peerId == myPeerId && !isGateway {
            becomeGateway()
        } else if winner.peerId != myPeerId && isGateway {
            resignAsGateway()
        }

        if previousGateway != gatewayPeerId {
            onGatewayChanged?(gatewayPeerId)
        }
    }

    private func calculateGatewayScore(signalStrength: Int, battery: Int) -> Int {
        // Score formula: signal weight (60%) + battery weight (40%)
        // Signal: 0-4, Battery: 0-100
        let signalScore = signalStrength * 25 // 0-100
        let batteryScore = battery
        return (signalScore * 60 + batteryScore * 40) / 100
    }

    private func becomeGateway() {
        isGateway = true
        onBecomeGateway?()
        Log.gatewayInfo("This device is now the gateway")
    }

    private func resignAsGateway() {
        guard isGateway else { return }
        isGateway = false
        onResignGateway?()
        print("[Gateway] Resigned as gateway")
    }

    // MARK: - Network Monitoring

    /// Restart the path monitor to pick up connectivity changes (e.g. after airplane mode toggle)
    func refreshNetworkStatus() {
        pathMonitor?.cancel()
        pathMonitor = nil
        setupNetworkMonitoring()
    }

    private func setupNetworkMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.applyPathUpdate(path)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }

    private func applyPathUpdate(_ path: NWPath) {
        hasInternetAccess = path.status == .satisfied

        // Estimate signal strength from path properties
        if path.usesInterfaceType(.cellular) {
            signalStrength = path.isConstrained ? 2 : 4
        } else if path.usesInterfaceType(.wifi) {
            signalStrength = path.isExpensive ? 3 : 4
        } else {
            signalStrength = 0
        }
    }

    // MARK: - Battery Monitoring

    private func setupBatteryMonitoring() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryLevel()

        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBatteryLevel()
        }
        #endif
    }

    private func updateBatteryLevel() {
        #if os(iOS)
        let level = UIDevice.current.batteryLevel
        batteryLevel = level < 0 ? 100 : Int(level * 100)

        // Check if we should rotate gateway due to low battery
        if isGateway && batteryLevel < gatewayRotationBattery {
            performElection()
        }
        #endif
    }
}

#if os(iOS)
import UIKit
#endif
