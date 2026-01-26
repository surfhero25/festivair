import Foundation
import CoreLocation
import Combine

/// Manages proximity-based haptic feedback for navigation to squad members.
/// Uses battery-efficient timer-based polling instead of continuous updates.
final class ProximityHapticsManager: ObservableObject {

    // MARK: - State
    @Published private(set) var isActive = false
    @Published private(set) var currentDistance: Double?
    @Published private(set) var proximityLevel: ProximityLevel = .far

    // MARK: - Configuration
    enum ProximityLevel: Comparable {
        case far        // >200m - no haptics
        case approaching // 100-200m - light pulse every 10 sec
        case near       // 50-100m - light pulse every 5 sec
        case close      // 20-50m - medium pulse every 2 sec
        case veryClose  // <20m - continuous light pulses

        var hapticInterval: TimeInterval? {
            switch self {
            case .far: return nil
            case .approaching: return 10.0
            case .near: return 5.0
            case .close: return 2.0
            case .veryClose: return 0.5
            }
        }

        var description: String {
            switch self {
            case .far: return "Far away"
            case .approaching: return "Approaching"
            case .near: return "Getting close"
            case .close: return "Very close"
            case .veryClose: return "Almost there!"
            }
        }

        static func from(distance: Double) -> ProximityLevel {
            switch distance {
            case 0..<20: return .veryClose
            case 20..<50: return .close
            case 50..<100: return .near
            case 100..<200: return .approaching
            default: return .far
            }
        }
    }

    // MARK: - Private
    private var hapticTimer: Timer?
    private var targetCoordinate: CLLocationCoordinate2D?
    private var locationUpdateHandler: (() -> CLLocationCoordinate2D?)?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle
    deinit {
        stopTracking()
    }

    // MARK: - Public API

    /// Start proximity haptics to a target coordinate.
    /// - Parameters:
    ///   - target: The target coordinate to navigate toward
    ///   - locationProvider: Closure that returns the current user location
    func startTracking(
        target: CLLocationCoordinate2D,
        locationProvider: @escaping () -> CLLocationCoordinate2D?
    ) {
        stopTracking()

        targetCoordinate = target
        locationUpdateHandler = locationProvider
        isActive = true

        // Start polling timer (every 1 second for distance checks)
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateProximity()
        }
    }

    /// Update the target coordinate (when member moves)
    func updateTarget(_ coordinate: CLLocationCoordinate2D) {
        targetCoordinate = coordinate
    }

    /// Stop tracking and haptics
    func stopTracking() {
        hapticTimer?.invalidate()
        hapticTimer = nil
        targetCoordinate = nil
        locationUpdateHandler = nil
        isActive = false
        currentDistance = nil
        proximityLevel = .far
    }

    // MARK: - Private

    private var lastHapticTime: Date?

    private func updateProximity() {
        guard let target = targetCoordinate,
              let userCoord = locationUpdateHandler?() else { return }

        let userLocation = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
        let distance = userLocation.distance(from: targetLocation)

        let newLevel = ProximityLevel.from(distance: distance)
        let previousLevel = proximityLevel

        DispatchQueue.main.async {
            self.currentDistance = distance
            self.proximityLevel = newLevel
        }

        // Check if we should trigger haptic
        if let interval = newLevel.hapticInterval {
            let now = Date()
            if lastHapticTime == nil || now.timeIntervalSince(lastHapticTime!) >= interval {
                triggerHaptic(for: newLevel)
                lastHapticTime = now
            }
        }

        // Extra feedback when transitioning to closer level
        if newLevel > previousLevel && newLevel != .far {
            triggerTransitionHaptic(to: newLevel)
        }

        // Success haptic when arriving
        if newLevel == .veryClose && previousLevel != .veryClose {
            Haptics.success()
        }
    }

    private func triggerHaptic(for level: ProximityLevel) {
        switch level {
        case .far:
            break // No haptics
        case .approaching, .near:
            Haptics.light()
        case .close:
            Haptics.medium()
        case .veryClose:
            Haptics.light()
        }
    }

    private func triggerTransitionHaptic(to level: ProximityLevel) {
        // Give extra feedback when getting significantly closer
        switch level {
        case .close, .veryClose:
            Haptics.medium()
        case .near:
            Haptics.light()
        default:
            break
        }
    }
}
