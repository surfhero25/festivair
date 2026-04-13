import Foundation
import UIKit
import Combine

/// Monitors battery drain rate and adapts FestivAir behavior.
/// High drain (video recording) → ultra-conservative mode.
/// Normal drain → standard behavior.
final class FestivalModeManager: ObservableObject {

    // MARK: - Types

    enum DrainLevel: String {
        case normal     // ~5-8%/hr — standard behavior
        case elevated   // ~10-15%/hr — reduce presence pulse
        case high       // ~15-25%/hr — ultra conservative
        case critical   // >25%/hr — near silent
    }

    // MARK: - Published State

    @Published private(set) var drainLevel: DrainLevel = .normal
    @Published private(set) var drainRatePerHour: Float = 0  // estimated %/hr

    // MARK: - Configuration

    private let sampleInterval: TimeInterval = 300  // 5 minutes
    private let elevatedThreshold: Float = 10.0     // %/hr
    private let highThreshold: Float = 15.0
    private let criticalThreshold: Float = 25.0

    // MARK: - Sampling State

    private var batteryHistory: [(date: Date, level: Float)] = []
    private var sampleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks

    /// Called when drain level changes — MeshCoordinator should adjust behavior
    var onDrainLevelChanged: ((DrainLevel) -> Void)?

    // MARK: - Init

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        startMonitoring()
    }

    deinit {
        sampleTimer?.invalidate()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Record initial sample
        recordSample()

        // Sample every 5 minutes
        sampleTimer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.recordSample()
            self?.calculateDrainRate()
        }
    }

    private func recordSample() {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return }  // -1 means monitoring disabled
        batteryHistory.append((date: Date(), level: level * 100))

        // Keep only last 30 minutes of history
        let cutoff = Date().addingTimeInterval(-1800)
        batteryHistory.removeAll { $0.date < cutoff }
    }

    private func calculateDrainRate() {
        guard batteryHistory.count >= 2 else { return }

        let oldest = batteryHistory.first!
        let newest = batteryHistory.last!
        let timeDelta = newest.date.timeIntervalSince(oldest.date)

        guard timeDelta > 60 else { return }  // Need at least 1 minute of data

        let levelDelta = oldest.level - newest.level  // Positive = draining
        let hoursElapsed = Float(timeDelta) / 3600.0
        let rate = max(0, levelDelta / hoursElapsed)

        drainRatePerHour = rate

        let previousLevel = drainLevel
        if rate >= criticalThreshold {
            drainLevel = .critical
        } else if rate >= highThreshold {
            drainLevel = .high
        } else if rate >= elevatedThreshold {
            drainLevel = .elevated
        } else {
            drainLevel = .normal
        }

        if drainLevel != previousLevel {
            onDrainLevelChanged?(drainLevel)
        }
    }

    // MARK: - V2 Protocol Adjustments

    /// Returns the adjusted presence pulse interval based on drain level
    var adjustedPresencePulseInterval: TimeInterval {
        switch drainLevel {
        case .normal:   return Constants.ProtocolV2.presencePulseInterval      // 5 min
        case .elevated: return 480                                              // 8 min
        case .high:     return 600                                              // 10 min
        case .critical: return 900                                              // 15 min
        }
    }

    /// Returns the adjusted ambient response interval
    var adjustedAmbientInterval: TimeInterval {
        switch drainLevel {
        case .normal:   return Constants.ProtocolV2.ambientResponseInterval     // 60s
        case .elevated: return 90                                               // 90s
        case .high:     return 120                                              // 2 min
        case .critical: return 120                                              // 2 min
        }
    }

    /// Whether urgent chat should be delivered immediately
    var shouldDeliverUrgentChat: Bool {
        drainLevel != .critical  // Only suppress at critical drain
    }

    /// Whether this device should accept reporter role
    var canBeReporter: Bool {
        drainLevel == .normal || drainLevel == .elevated
    }
}
