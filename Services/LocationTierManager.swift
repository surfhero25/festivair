import Foundation
import Combine

/// Manages the location tier state machine: IDLE → AMBIENT → NAVIGATE
/// A device is always in the highest state that any peer has requested.
final class LocationTierManager: ObservableObject {

    // MARK: - Types

    enum LocationTier: String, Comparable {
        case idle
        case ambient
        case navigate

        static func < (lhs: LocationTier, rhs: LocationTier) -> Bool {
            let order: [LocationTier] = [.idle, .ambient, .navigate]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    /// Tracks who is requesting what from us
    struct ActiveRequest {
        let requesterID: String
        var tier: LocationTier
        let targetMemberID: String?  // Only set for NAVIGATE (who they're navigating to)
        var lastRenewal: Date
    }

    // MARK: - Published State

    @Published private(set) var currentTier: LocationTier = .idle
    @Published private(set) var activeRequests: [String: ActiveRequest] = [:]  // keyed by requesterID
    @Published private(set) var isInSOS: Bool = false

    // MARK: - Callbacks

    /// Called when tier changes — LocationManager should reconfigure GPS
    var onTierChanged: ((LocationTier) -> Void)?

    /// Called when a specific peer needs a precise location response
    var onPreciseLocationNeeded: ((String) -> Void)?  // requesterID

    // MARK: - Private

    private let myUserId: String
    private var timeoutTimer: Timer?
    private let sessionTimeout: TimeInterval

    // MARK: - Init

    init(userId: String, sessionTimeout: TimeInterval = Constants.ProtocolV2.sessionTimeout) {
        self.myUserId = userId
        self.sessionTimeout = sessionTimeout
        startTimeoutTimer()
    }

    deinit {
        timeoutTimer?.invalidate()
    }

    // MARK: - Incoming Request Handling

    /// Called when we receive a locationRequest from a peer (they opened their map)
    func handleLocationRequest(from requesterID: String) {
        let request = ActiveRequest(
            requesterID: requesterID,
            tier: .ambient,
            targetMemberID: nil,
            lastRenewal: Date()
        )
        activeRequests[requesterID] = request
        recalculateTier()
    }

    /// Called when we receive a preciseLocationRequest (someone is navigating to us or our cluster)
    func handlePreciseLocationRequest(from requesterID: String, targetMemberID: String) {
        let request = ActiveRequest(
            requesterID: requesterID,
            tier: .navigate,
            targetMemberID: targetMemberID,
            lastRenewal: Date()
        )
        activeRequests[requesterID] = request
        recalculateTier()
        onPreciseLocationNeeded?(requesterID)
    }

    /// Called when we receive a stopPreciseLocation
    func handleStopPreciseLocation(from requesterID: String) {
        activeRequests.removeValue(forKey: requesterID)
        recalculateTier()
    }

    /// Called when we receive a requestRenewal — keeps the session alive
    func handleRequestRenewal(from requesterID: String, mode: RenewalMode) {
        if var request = activeRequests[requesterID] {
            request.lastRenewal = Date()
            request.tier = mode == .precise ? .navigate : .ambient
            activeRequests[requesterID] = request  // Structs are value types
        }
        // If no existing request, treat renewal as a new request
        else {
            switch mode {
            case .ambient:
                handleLocationRequest(from: requesterID)
            case .precise:
                handlePreciseLocationRequest(from: requesterID, targetMemberID: myUserId)
            }
        }
    }

    // MARK: - SOS Override

    /// SOS overrides all tiers — broadcasts precise GPS continuously
    func activateSOS() {
        isInSOS = true
        recalculateTier()
    }

    func deactivateSOS() {
        isInSOS = false
        recalculateTier()
    }

    // MARK: - Tier Calculation

    /// The current tier is the HIGHEST tier requested by any active peer, or NAVIGATE if SOS
    private func recalculateTier() {
        let previousTier = currentTier

        if isInSOS {
            currentTier = .navigate
        } else if activeRequests.isEmpty {
            currentTier = .idle
        } else {
            currentTier = activeRequests.values.map(\.tier).max() ?? .idle
        }

        if currentTier != previousTier {
            onTierChanged?(currentTier)
        }
    }

    // MARK: - Timeout Management

    /// Checks every 15 seconds for expired requests
    private func startTimeoutTimer() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.cleanExpiredRequests()
        }
    }

    private func cleanExpiredRequests() {
        let cutoff = Date().addingTimeInterval(-sessionTimeout)
        let expired = activeRequests.filter { $0.value.lastRenewal < cutoff }

        for (key, _) in expired {
            activeRequests.removeValue(forKey: key)
        }

        if !expired.isEmpty {
            recalculateTier()
        }
    }

    // MARK: - Query

    /// Returns the list of requester IDs that need ambient responses
    var ambientRequesters: [String] {
        activeRequests.filter { $0.value.tier == .ambient }.map(\.key)
    }

    /// Returns the list of requester IDs that need precise responses
    var navigateRequesters: [String] {
        activeRequests.filter { $0.value.tier == .navigate }.map(\.key)
    }

    /// How many peers are actively watching us
    var viewerCount: Int {
        activeRequests.count
    }
}
