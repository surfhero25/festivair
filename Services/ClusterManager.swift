import Foundation
import Combine

/// Manages cluster formation, reporter election, and centroid calculation.
/// A cluster is 2+ squad members within ~5 meters of each other.
final class ClusterManager: ObservableObject {

    // MARK: - Types

    enum ClusterRole: String {
        case reporter   // Runs GPS, broadcasts for cluster
        case backup     // Ready to take over
        case passive    // GPS off, contributes nothing
        case solo       // Not in any cluster
    }

    struct ClusterMember {
        let userId: String
        var batteryLevel: Int      // 0-100
        var lastLocation: (lat: Double, lng: Double)?
        var lastSeen: Date
    }

    // MARK: - Published State

    @Published private(set) var clusterID: String?           // nil if solo
    @Published private(set) var myRole: ClusterRole = .solo
    @Published private(set) var clusterMembers: [String] = []  // userIds in my cluster
    @Published private(set) var reporterID: String?
    @Published private(set) var centroidLatitude: Double?
    @Published private(set) var centroidLongitude: Double?

    // MARK: - Configuration

    private let myUserId: String
    private let proximityThresholdMeters: Double = 5.0
    private let electionIntervalSeconds: TimeInterval = 300  // 5 minutes
    private let rotationBatteryDelta: Int = 10  // rotate if reporter drops 10%+ below backup
    private let lowBatteryThreshold: Int = 30
    private let roundRobinInterval: TimeInterval = 120  // 2 minutes when all low battery

    // MARK: - Internal State

    private var knownPeers: [String: ClusterMember] = [:]  // all squad peers with locations
    private var electionTimer: Timer?
    private var roundRobinTimer: Timer?
    private var roundRobinIndex: Int = 0

    // MARK: - Callbacks

    /// Called when this device becomes or stops being the reporter
    var onRoleChanged: ((ClusterRole) -> Void)?

    /// Called when reporter needs to send clusterHandoff to new reporter
    var onHandoffNeeded: ((String, Double, Double, Double) -> Void)?  // newReporterID, lat, lng, accuracy

    // MARK: - Init

    init(userId: String) {
        self.myUserId = userId
        startElectionTimer()
    }

    deinit {
        electionTimer?.invalidate()
        roundRobinTimer?.invalidate()
    }

    // MARK: - Peer Updates

    /// Called when we receive a presencePulse or locationResponse from a squad member
    func updatePeer(userId: String, batteryLevel: Int, latitude: Double?, longitude: Double?) {
        var member = knownPeers[userId] ?? ClusterMember(
            userId: userId,
            batteryLevel: batteryLevel,
            lastLocation: nil,
            lastSeen: Date()
        )
        member.batteryLevel = batteryLevel
        member.lastSeen = Date()
        if let lat = latitude, let lng = longitude {
            member.lastLocation = (lat, lng)
        }
        knownPeers[userId] = member
        evaluateClusters()
    }

    /// Called when a peer disconnects
    func removePeer(userId: String) {
        knownPeers.removeValue(forKey: userId)
        evaluateClusters()
    }

    /// Update own battery level
    func updateMyBattery(_ level: Int) {
        var me = knownPeers[myUserId] ?? ClusterMember(
            userId: myUserId, batteryLevel: level, lastLocation: nil, lastSeen: Date()
        )
        me.batteryLevel = level
        me.lastSeen = Date()
        knownPeers[myUserId] = me
    }

    /// Update own location
    func updateMyLocation(latitude: Double, longitude: Double) {
        var me = knownPeers[myUserId] ?? ClusterMember(
            userId: myUserId, batteryLevel: 100, lastLocation: nil, lastSeen: Date()
        )
        me.lastLocation = (latitude, longitude)
        me.lastSeen = Date()
        knownPeers[myUserId] = me
        evaluateClusters()
        updateCentroid()
    }

    // MARK: - Cluster Evaluation

    private func evaluateClusters() {
        guard let myLoc = knownPeers[myUserId]?.lastLocation else {
            // No location — can't cluster
            if clusterID != nil { leaveCluster() }
            return
        }

        // Find all peers within proximity threshold
        var nearbyPeers: [String] = []
        for (peerId, peer) in knownPeers {
            guard peerId != myUserId, let peerLoc = peer.lastLocation else { continue }
            let distance = haversineDistance(
                lat1: myLoc.lat, lon1: myLoc.lng,
                lat2: peerLoc.lat, lon2: peerLoc.lng
            )
            if distance <= proximityThresholdMeters {
                nearbyPeers.append(peerId)
            }
        }

        if nearbyPeers.isEmpty {
            // Solo — no one nearby
            if clusterID != nil { leaveCluster() }
            return
        }

        // Form or maintain cluster
        let allMembers = [myUserId] + nearbyPeers
        if clusterID == nil {
            // New cluster
            clusterID = UUID().uuidString
            clusterMembers = allMembers
            electReporter()
        } else {
            // Update existing cluster membership
            clusterMembers = allMembers
            // Re-elect if reporter left the cluster
            if let reporter = reporterID, !allMembers.contains(reporter) {
                electReporter()
            }
        }
    }

    private func leaveCluster() {
        clusterID = nil
        clusterMembers = []
        reporterID = nil
        centroidLatitude = nil
        centroidLongitude = nil
        let previousRole = myRole
        myRole = .solo
        if previousRole != .solo {
            onRoleChanged?(.solo)
        }
        roundRobinTimer?.invalidate()
        roundRobinTimer = nil
    }

    // MARK: - Reporter Election

    private func electReporter() {
        guard !clusterMembers.isEmpty else { return }

        // Sort by battery level descending
        let sorted = clusterMembers.compactMap { id -> (String, Int)? in
            guard let peer = knownPeers[id] else { return nil }
            return (id, peer.batteryLevel)
        }.sorted { $0.1 > $1.1 }

        guard let highest = sorted.first else { return }

        let allLowBattery = sorted.allSatisfy { $0.1 < lowBatteryThreshold }

        if allLowBattery {
            startRoundRobin()
            return
        }

        roundRobinTimer?.invalidate()
        roundRobinTimer = nil

        let previousReporter = reporterID
        reporterID = highest.0

        // Assign roles
        let previousRole = myRole
        if myUserId == reporterID {
            myRole = .reporter
        } else if sorted.count > 1 && myUserId == sorted[1].0 {
            myRole = .backup
        } else {
            myRole = .passive
        }

        if myRole != previousRole {
            onRoleChanged?(myRole)
        }

        // If reporter changed and we were the old reporter, trigger handoff
        if previousReporter == myUserId && reporterID != myUserId {
            if let loc = knownPeers[myUserId]?.lastLocation {
                onHandoffNeeded?(reporterID!, loc.lat, loc.lng, 10.0)  // accuracy estimate
            }
        }
    }

    private func startRoundRobin() {
        guard !clusterMembers.isEmpty else { return }
        roundRobinIndex = 0
        assignRoundRobinReporter()

        roundRobinTimer?.invalidate()
        roundRobinTimer = Timer.scheduledTimer(withTimeInterval: roundRobinInterval, repeats: true) { [weak self] _ in
            self?.advanceRoundRobin()
        }
    }

    private func advanceRoundRobin() {
        guard !clusterMembers.isEmpty else { return }
        roundRobinIndex = (roundRobinIndex + 1) % clusterMembers.count
        assignRoundRobinReporter()
    }

    private func assignRoundRobinReporter() {
        let newReporter = clusterMembers[roundRobinIndex % clusterMembers.count]
        let previousReporter = reporterID
        reporterID = newReporter

        let previousRole = myRole
        myRole = (myUserId == newReporter) ? .reporter : .passive

        if myRole != previousRole {
            onRoleChanged?(myRole)
        }

        if previousReporter == myUserId && reporterID != myUserId {
            if let loc = knownPeers[myUserId]?.lastLocation {
                onHandoffNeeded?(reporterID!, loc.lat, loc.lng, 10.0)
            }
        }
    }

    // MARK: - Centroid Calculation

    private func updateCentroid() {
        guard clusterID != nil else {
            centroidLatitude = nil
            centroidLongitude = nil
            return
        }

        var totalLat = 0.0
        var totalLng = 0.0
        var totalWeight = 0.0

        for memberId in clusterMembers {
            guard let member = knownPeers[memberId], let loc = member.lastLocation else { continue }
            // Reporter's GPS gets highest weight, others get lower
            let weight: Double = (memberId == reporterID) ? 3.0 : 1.0
            totalLat += loc.lat * weight
            totalLng += loc.lng * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return }
        centroidLatitude = totalLat / totalWeight
        centroidLongitude = totalLng / totalWeight
    }

    // MARK: - Election Timer

    private func startElectionTimer() {
        electionTimer = Timer.scheduledTimer(withTimeInterval: electionIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self, self.clusterID != nil else { return }
            self.checkRotation()
        }
    }

    private func checkRotation() {
        guard let currentReporter = reporterID,
              let reporterBattery = knownPeers[currentReporter]?.batteryLevel else { return }

        // Find backup (second highest battery)
        let sorted = clusterMembers.compactMap { id -> (String, Int)? in
            guard let peer = knownPeers[id], id != currentReporter else { return nil }
            return (id, peer.batteryLevel)
        }.sorted { $0.1 > $1.1 }

        guard let backup = sorted.first else { return }

        // Rotate if reporter dropped 10%+ below backup
        if backup.1 - reporterBattery >= rotationBatteryDelta {
            electReporter()
            return
        }

        // Immediate rotation if reporter below 30%
        if reporterBattery < lowBatteryThreshold {
            electReporter()
        }
    }

    // MARK: - Haversine Distance

    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0  // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    // MARK: - Cleanup

    /// Remove peers not seen in the last 5 minutes
    func cleanupStalePeers() {
        let cutoff = Date().addingTimeInterval(-300)
        let stale = knownPeers.filter { $0.key != myUserId && $0.value.lastSeen < cutoff }
        for (key, _) in stale {
            knownPeers.removeValue(forKey: key)
        }
        if !stale.isEmpty {
            evaluateClusters()
        }
    }
}
