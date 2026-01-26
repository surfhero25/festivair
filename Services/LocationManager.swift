import Foundation
import CoreLocation
import Combine

/// Manages device location with battery-optimized update strategies
final class LocationManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published private(set) var currentLocation: Location?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isUpdating = false
    @Published private(set) var lastError: Error?
    @Published private(set) var deviceHeading: Double? // Compass heading in degrees (0-360, 0 = North)

    // MARK: - Configuration
    enum UpdateMode {
        case active      // App in foreground, 30 sec updates
        case background  // App backgrounded, 2 min updates
        case lowPower    // User-enabled battery saver, 5 min updates
        case stationary  // Not moving, 10 min updates

        var updateInterval: TimeInterval {
            switch self {
            case .active: return 30
            case .background: return 120
            case .lowPower: return 300
            case .stationary: return 600
            }
        }

        var desiredAccuracy: CLLocationAccuracy {
            switch self {
            case .active: return kCLLocationAccuracyNearestTenMeters
            case .background: return kCLLocationAccuracyHundredMeters
            case .lowPower: return kCLLocationAccuracyHundredMeters
            case .stationary: return kCLLocationAccuracyKilometer
            }
        }
    }

    @Published var updateMode: UpdateMode = .active {
        didSet {
            if isUpdating {
                configureLocationManager()
            }
        }
    }

    // MARK: - Private
    private let locationManager = CLLocationManager()
    private var updateTimer: Timer?
    private var lastUpdateTime: Date?

    // MARK: - Callbacks
    var onLocationUpdate: ((Location) -> Void)?

    // MARK: - Init
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
    }

    private var isHeadingUpdating = false

    deinit {
        updateTimer?.invalidate()
    }

    // MARK: - Public API

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    func startUpdating() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestAuthorization()
            return
        }

        configureLocationManager()
        locationManager.startUpdatingLocation()
        isUpdating = true

        // Start periodic update timer
        startUpdateTimer()
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
        updateTimer?.invalidate()
        updateTimer = nil
        isUpdating = false
    }

    /// Temporarily boost location accuracy for "Find Me" feature
    func enableFindMeMode(duration: TimeInterval = 60) {
        let previousMode = updateMode
        updateMode = .active
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.updateMode = previousMode
        }
    }

    // MARK: - Heading Updates (Compass)

    /// Start receiving heading updates for compass navigation
    func startHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else {
            print("[Location] Heading not available on this device")
            return
        }

        locationManager.headingFilter = 5 // Update every 5 degrees of change
        locationManager.startUpdatingHeading()
        isHeadingUpdating = true
    }

    /// Stop receiving heading updates
    func stopHeadingUpdates() {
        locationManager.stopUpdatingHeading()
        isHeadingUpdating = false
        deviceHeading = nil
    }

    // MARK: - Private Helpers

    private func configureLocationManager() {
        locationManager.desiredAccuracy = updateMode.desiredAccuracy
        locationManager.distanceFilter = updateMode == .active ? 10 : 50
    }

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateMode.updateInterval, repeats: true) { [weak self] _ in
            self?.locationManager.requestLocation()
        }
    }

    private func processLocation(_ clLocation: CLLocation) {
        let location = Location(
            latitude: clLocation.coordinate.latitude,
            longitude: clLocation.coordinate.longitude,
            accuracy: clLocation.horizontalAccuracy,
            timestamp: clLocation.timestamp,
            source: .gps
        )

        // Throttle updates based on mode
        if let lastTime = lastUpdateTime,
           Date().timeIntervalSince(lastTime) < updateMode.updateInterval / 2 {
            return
        }

        currentLocation = location
        lastUpdateTime = Date()
        onLocationUpdate?(location)
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        processLocation(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error
        print("[Location] Error: \(error)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Use true heading if available (more accurate), otherwise magnetic heading
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        DispatchQueue.main.async {
            self.deviceHeading = heading
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus

            switch self.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.isUpdating {
                    self.locationManager.startUpdatingLocation()
                }
            case .denied, .restricted:
                self.stopUpdating()
            default:
                break
            }
        }
    }
}

// MARK: - Stationary Detection
extension LocationManager {

    /// Detect if user is stationary based on recent locations
    func checkIfStationary(threshold: CLLocationDistance = 20) -> Bool {
        // This would compare recent locations to detect movement
        // For now, return false - would need location history
        return false
    }
}
