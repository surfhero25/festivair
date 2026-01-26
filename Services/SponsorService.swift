import Foundation
import CoreLocation
import UserNotifications

/// Service for managing sponsor activations and geofencing
@MainActor
final class SponsorService: ObservableObject {

    // MARK: - Singleton
    static let shared = SponsorService()

    // MARK: - Published State
    @Published private(set) var activations: [SponsorActivation] = []
    @Published private(set) var nearbyActivations: [SponsorActivation] = []
    @Published private(set) var claimedRewards: Set<String> = []  // Activation IDs
    @Published private(set) var isLoading = false

    // MARK: - Private
    private let apiBaseURL = "https://api.festivair.app/sponsors"  // TODO: Configure
    private var lastUserLocation: CLLocationCoordinate2D?
    private let nearbyRadius: Double = Constants.Sponsor.nearbyRadiusMeters

    // MARK: - Init
    private init() {
        loadClaimedRewards()
    }

    // MARK: - Fetch Activations

    /// Fetch activations for a specific event
    func fetchActivations(eventId: String) async {
        isLoading = true

        // In production, fetch from API
        // let url = URL(string: "\(apiBaseURL)/events/\(eventId)/activations")!
        // let (data, _) = try await URLSession.shared.data(from: url)
        // activations = try JSONDecoder().decode([SponsorActivation].self, from: data)

        // For now, use sample data
        activations = SponsorActivation.samples

        updateNearbyActivations()

        isLoading = false
    }

    /// Fetch activations near a location
    func fetchActivationsNear(latitude: Double, longitude: Double, radiusKm: Double = 10) async {
        isLoading = true

        // In production, fetch from API with location params
        // let url = URL(string: "\(apiBaseURL)/near?lat=\(latitude)&lon=\(longitude)&radius=\(radiusKm)")!
        // ...

        // For now, use sample data filtered by distance
        let userLocation = CLLocation(latitude: latitude, longitude: longitude)
        activations = SponsorActivation.samples.filter { activation in
            let activationLocation = CLLocation(latitude: activation.latitude, longitude: activation.longitude)
            let distanceKm = userLocation.distance(from: activationLocation) / 1000
            return distanceKm <= radiusKm && activation.isHappeningNow
        }

        lastUserLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        updateNearbyActivations()

        isLoading = false
    }

    // MARK: - Location Updates

    /// Update user location and check for nearby activations
    func updateUserLocation(latitude: Double, longitude: Double) {
        lastUserLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        updateNearbyActivations()
        checkGeofences(latitude: latitude, longitude: longitude)
    }

    private func updateNearbyActivations() {
        guard let userLoc = lastUserLocation else {
            nearbyActivations = []
            return
        }

        let userLocation = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)

        nearbyActivations = activations.filter { activation in
            let activationLocation = CLLocation(latitude: activation.latitude, longitude: activation.longitude)
            let distance = userLocation.distance(from: activationLocation)
            return distance <= nearbyRadius && activation.isHappeningNow
        }.sorted { a, b in
            let aLoc = CLLocation(latitude: a.latitude, longitude: a.longitude)
            let bLoc = CLLocation(latitude: b.latitude, longitude: b.longitude)
            return userLocation.distance(from: aLoc) < userLocation.distance(from: bLoc)
        }
    }

    // MARK: - Geofencing

    private func checkGeofences(latitude: Double, longitude: Double) {
        for activation in activations {
            guard activation.isHappeningNow,
                  !claimedRewards.contains(activation.id) else {
                continue
            }

            if activation.isUserInRange(userLatitude: latitude, userLongitude: longitude) {
                // User entered activation zone
                sendActivationNotification(activation)
            }
        }
    }

    private func sendActivationNotification(_ activation: SponsorActivation) {
        let content = UNMutableNotificationContent()
        content.title = "\(activation.sponsorName) Activation!"
        content.body = activation.title
        content.sound = .default
        content.categoryIdentifier = "SPONSOR_ACTIVATION"
        content.userInfo = ["activationId": activation.id]

        let request = UNNotificationRequest(
            identifier: "sponsor_\(activation.id)",
            content: content,
            trigger: nil  // Immediate
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Claim Reward

    /// Claim a reward from an activation
    func claimReward(activationId: String) async throws -> String? {
        guard let activation = activations.first(where: { $0.id == activationId }) else {
            throw SponsorError.activationNotFound
        }

        guard activation.isHappeningNow else {
            throw SponsorError.activationExpired
        }

        guard !claimedRewards.contains(activationId) else {
            throw SponsorError.alreadyClaimed
        }

        // In production, verify claim with API
        // let url = URL(string: "\(apiBaseURL)/activations/\(activationId)/claim")!
        // ...

        // Mark as claimed
        claimedRewards.insert(activationId)
        saveClaimedRewards()

        return activation.rewardCode
    }

    /// Check if a reward has been claimed
    func hasClaimedReward(activationId: String) -> Bool {
        claimedRewards.contains(activationId)
    }

    // MARK: - Persistence

    private func loadClaimedRewards() {
        if let data = UserDefaults.standard.data(forKey: "FestivAir.ClaimedRewards"),
           let rewards = try? JSONDecoder().decode(Set<String>.self, from: data) {
            claimedRewards = rewards
        }
    }

    private func saveClaimedRewards() {
        if let data = try? JSONEncoder().encode(claimedRewards) {
            UserDefaults.standard.set(data, forKey: "FestivAir.ClaimedRewards")
        }
    }

    // MARK: - Analytics (Anonymized)

    /// Report that user viewed an activation (for sponsor analytics)
    func reportView(activationId: String) async {
        // In production, send anonymized view event to API
        // POST /activations/{id}/view
    }

    /// Report that user claimed a reward
    func reportClaim(activationId: String) async {
        // In production, send anonymized claim event to API
        // POST /activations/{id}/claim-event
    }
}

// MARK: - Errors

enum SponsorError: LocalizedError {
    case activationNotFound
    case activationExpired
    case alreadyClaimed
    case claimFailed

    var errorDescription: String? {
        switch self {
        case .activationNotFound: return "Activation not found"
        case .activationExpired: return "This activation has ended"
        case .alreadyClaimed: return "You've already claimed this reward"
        case .claimFailed: return "Failed to claim reward"
        }
    }
}
