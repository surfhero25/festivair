import Foundation
import SwiftUI
import MapKit
import Combine
import CoreLocation

@MainActor
final class MapViewModel: ObservableObject {

    // MARK: - Published State
    @Published var region: MKCoordinateRegion = .init(
        center: CLLocationCoordinate2D(latitude: 36.2697, longitude: -115.0078), // Default: Las Vegas
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Published var memberAnnotations: [MemberAnnotation] = []
    @Published var selectedMember: MemberAnnotation?
    @Published var isFindMeActive = false
    @Published var showOfflineMembers = true

    // MARK: - Group Positioning
    @Published var groupCentroid: GroupCentroid?
    @Published var isCollaborativeGPSEnabled = true

    // MARK: - Dependencies
    private let locationManager: LocationManager
    private let meshManager: MeshNetworkManager
    private let peerTracker: PeerTracker
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Current User
    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId)
    }

    // MARK: - Init
    init(locationManager: LocationManager, meshManager: MeshNetworkManager, peerTracker: PeerTracker) {
        self.locationManager = locationManager
        self.meshManager = meshManager
        self.peerTracker = peerTracker
        setupBindings()
    }

    // MARK: - Map Operations

    func centerOnUser() {
        guard let location = locationManager.currentLocation else { return }
        withAnimation {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }
    }

    func centerOnMember(_ annotation: MemberAnnotation) {
        withAnimation {
            region = MKCoordinateRegion(
                center: annotation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            )
        }
        selectedMember = annotation
    }

    func fitAllMembers() {
        guard !memberAnnotations.isEmpty else {
            centerOnUser()
            return
        }

        var minLat = memberAnnotations[0].coordinate.latitude
        var maxLat = minLat
        var minLon = memberAnnotations[0].coordinate.longitude
        var maxLon = minLon

        for annotation in memberAnnotations {
            minLat = min(minLat, annotation.coordinate.latitude)
            maxLat = max(maxLat, annotation.coordinate.latitude)
            minLon = min(minLon, annotation.coordinate.longitude)
            maxLon = max(maxLon, annotation.coordinate.longitude)
        }

        // Include user location
        if let userLoc = locationManager.currentLocation {
            minLat = min(minLat, userLoc.latitude)
            maxLat = max(maxLat, userLoc.latitude)
            minLon = min(minLon, userLoc.longitude)
            maxLon = max(maxLon, userLoc.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.002,
            longitudeDelta: (maxLon - minLon) * 1.5 + 0.002
        )

        withAnimation {
            region = MKCoordinateRegion(center: center, span: span)
        }
    }

    // MARK: - Find Me

    func activateFindMe() {
        guard let userId = currentUserId else { return }

        isFindMeActive = true
        locationManager.enableFindMeMode(duration: 60)

        // Broadcast find me
        let message = MeshMessagePayload(
            type: .findMe,
            userId: userId,
            location: nil,
            chat: nil,
            peerId: nil,
            signalStrength: nil,
            squadId: nil,
            syncData: nil,
            batteryLevel: nil,
            hasService: nil,
            enabled: true
        )
        meshManager.broadcast(message)

        // Reset after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.isFindMeActive = false
        }
    }

    // MARK: - Private Helpers

    private func setupBindings() {
        // Update annotations when peer status changes
        peerTracker.$onlinePeers
            .combineLatest(peerTracker.$offlinePeers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] online, offline in
                self?.updateAnnotations(online: online, offline: offline)
            }
            .store(in: &cancellables)

        // Center on user when first location arrives
        locationManager.$currentLocation
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
            .store(in: &cancellables)
    }

    private func updateAnnotations(online: [PeerTracker.PeerStatus], offline: [PeerTracker.PeerStatus]) {
        var annotations: [MemberAnnotation] = []
        var locationsWithAccuracy: [(coordinate: CLLocationCoordinate2D, accuracy: Double, isOnline: Bool)] = []

        // Get user location for distance calculations
        let userLocation = locationManager.currentLocation

        for peer in online {
            if let location = peer.location {
                let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)

                // Calculate distance from user
                let distanceFromUser = userLocation.map { userLoc -> Double in
                    let userCoord = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
                    let peerCoord = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    return userCoord.distance(from: peerCoord)
                }

                annotations.append(MemberAnnotation(
                    id: peer.id,
                    displayName: peer.displayName,
                    emoji: peer.emoji,
                    coordinate: coordinate,
                    isOnline: true,
                    batteryLevel: peer.batteryLevel,
                    hasService: peer.hasService,
                    lastSeen: peer.lastSeen,
                    isFindMeActive: false,
                    accuracy: location.accuracy,
                    distanceFromUser: distanceFromUser
                ))

                locationsWithAccuracy.append((coordinate, location.accuracy, true))
            }
        }

        if showOfflineMembers {
            for peer in offline {
                if let location = peer.location {
                    let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)

                    let distanceFromUser = userLocation.map { userLoc -> Double in
                        let userCoord = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
                        let peerCoord = CLLocation(latitude: location.latitude, longitude: location.longitude)
                        return userCoord.distance(from: peerCoord)
                    }

                    annotations.append(MemberAnnotation(
                        id: peer.id,
                        displayName: peer.displayName,
                        emoji: peer.emoji,
                        coordinate: coordinate,
                        isOnline: false,
                        batteryLevel: peer.batteryLevel,
                        hasService: peer.hasService,
                        lastSeen: peer.lastSeen,
                        isFindMeActive: false,
                        accuracy: location.accuracy,
                        distanceFromUser: distanceFromUser
                    ))

                    locationsWithAccuracy.append((coordinate, location.accuracy, false))
                }
            }
        }

        memberAnnotations = annotations

        // Calculate group centroid using collaborative GPS
        if isCollaborativeGPSEnabled {
            groupCentroid = calculateGroupCentroid(
                locations: locationsWithAccuracy,
                userLocation: userLocation
            )
        } else {
            groupCentroid = nil
        }
    }

    // MARK: - Collaborative GPS / Group Positioning

    /// Calculates a weighted centroid of the squad using GPS accuracy data.
    /// Members with better GPS accuracy contribute more to the final position.
    /// This helps the group find each other by providing a single "group center" point.
    private func calculateGroupCentroid(
        locations: [(coordinate: CLLocationCoordinate2D, accuracy: Double, isOnline: Bool)],
        userLocation: Location?
    ) -> GroupCentroid? {
        // Need at least 1 online member to calculate centroid
        let onlineLocations = locations.filter { $0.isOnline }
        guard !onlineLocations.isEmpty else { return nil }

        // Include user's location if available (with their GPS accuracy)
        var allLocations = onlineLocations
        if let userLoc = userLocation {
            allLocations.append((
                CLLocationCoordinate2D(latitude: userLoc.latitude, longitude: userLoc.longitude),
                userLoc.accuracy,
                true
            ))
        }

        // Calculate weighted average using inverse accuracy (lower accuracy = more weight)
        // GPS accuracy is in meters - lower is better
        var totalWeight: Double = 0
        var weightedLat: Double = 0
        var weightedLon: Double = 0

        for loc in allLocations {
            // Weight: inverse of accuracy, clamped to avoid division issues
            // Accuracy of 5m = weight of 0.2, accuracy of 50m = weight of 0.02
            let weight = 1.0 / max(loc.accuracy, 1.0)
            totalWeight += weight
            weightedLat += loc.coordinate.latitude * weight
            weightedLon += loc.coordinate.longitude * weight
        }

        guard totalWeight > 0 else { return nil }

        let centroidLat = weightedLat / totalWeight
        let centroidLon = weightedLon / totalWeight

        // Calculate the average accuracy of the centroid
        // The combined accuracy improves with more members (sqrt of sum of inverse variances)
        let combinedAccuracy = 1.0 / sqrt(allLocations.reduce(0.0) { sum, loc in
            sum + 1.0 / (loc.accuracy * loc.accuracy)
        })

        // Calculate distance from user to centroid
        let centroidCoord = CLLocationCoordinate2D(latitude: centroidLat, longitude: centroidLon)
        let distanceFromUser: Double? = userLocation.map { userLoc in
            let userCoord = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
            let centroid = CLLocation(latitude: centroidLat, longitude: centroidLon)
            return userCoord.distance(from: centroid)
        }

        // Calculate the spread (max distance between any member and centroid)
        var maxSpread: Double = 0
        for loc in onlineLocations {
            let memberLoc = CLLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            let centroidLoc = CLLocation(latitude: centroidLat, longitude: centroidLon)
            maxSpread = max(maxSpread, memberLoc.distance(from: centroidLoc))
        }

        return GroupCentroid(
            coordinate: centroidCoord,
            memberCount: onlineLocations.count,
            combinedAccuracy: combinedAccuracy,
            distanceFromUser: distanceFromUser,
            spreadRadius: maxSpread
        )
    }

    /// Center map on the group centroid
    func centerOnGroup() {
        guard let centroid = groupCentroid else {
            fitAllMembers()
            return
        }

        // Zoom level based on group spread
        let spanDelta = max(0.002, centroid.spreadRadius / 50000) // Rough conversion to degrees

        withAnimation {
            region = MKCoordinateRegion(
                center: centroid.coordinate,
                span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
            )
        }
    }
}

// MARK: - Member Annotation
struct MemberAnnotation: Identifiable {
    let id: String
    let displayName: String
    let emoji: String
    let coordinate: CLLocationCoordinate2D
    let isOnline: Bool
    let batteryLevel: Int?
    let hasService: Bool
    let lastSeen: Date
    let isFindMeActive: Bool
    let accuracy: Double?
    let distanceFromUser: Double?

    init(
        id: String,
        displayName: String,
        emoji: String,
        coordinate: CLLocationCoordinate2D,
        isOnline: Bool,
        batteryLevel: Int?,
        hasService: Bool,
        lastSeen: Date,
        isFindMeActive: Bool,
        accuracy: Double? = nil,
        distanceFromUser: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.emoji = emoji
        self.coordinate = coordinate
        self.isOnline = isOnline
        self.batteryLevel = batteryLevel
        self.hasService = hasService
        self.lastSeen = lastSeen
        self.isFindMeActive = isFindMeActive
        self.accuracy = accuracy
        self.distanceFromUser = distanceFromUser
    }

    var lastSeenText: String {
        if isOnline {
            return "Online now"
        }
        return lastSeen.timeAgo
    }

    /// Human-readable distance from current user
    var distanceText: String? {
        guard let distance = distanceFromUser else { return nil }

        if distance < 10 {
            return "Right here"
        } else if distance < 100 {
            return "\(Int(distance))m away"
        } else if distance < 1000 {
            let rounded = (Int(distance) / 10) * 10
            return "~\(rounded)m away"
        } else {
            let km = distance / 1000
            return String(format: "%.1fkm away", km)
        }
    }

    /// Accuracy quality indicator
    var accuracyQuality: AccuracyQuality {
        guard let acc = accuracy else { return .unknown }
        if acc <= 5 { return .excellent }
        if acc <= 15 { return .good }
        if acc <= 50 { return .fair }
        return .poor
    }

    enum AccuracyQuality {
        case excellent  // ≤5m - high confidence
        case good       // ≤15m - reliable
        case fair       // ≤50m - approximate
        case poor       // >50m - rough estimate
        case unknown

        var description: String {
            switch self {
            case .excellent: return "Precise location"
            case .good: return "Good accuracy"
            case .fair: return "Approximate"
            case .poor: return "Rough estimate"
            case .unknown: return "Unknown accuracy"
            }
        }

        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .fair: return .orange
            case .poor: return .red
            case .unknown: return .gray
            }
        }
    }
}

// MARK: - Group Centroid
/// Represents the calculated center point of all squad members,
/// weighted by GPS accuracy for better positioning.
struct GroupCentroid: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let memberCount: Int
    let combinedAccuracy: Double
    let distanceFromUser: Double?
    let spreadRadius: Double

    /// Human-readable distance from user to group center
    var distanceText: String? {
        guard let distance = distanceFromUser else { return nil }

        if distance < 10 {
            return "You're with the group"
        } else if distance < 100 {
            return "\(Int(distance))m to group"
        } else if distance < 1000 {
            let rounded = (Int(distance) / 10) * 10
            return "~\(rounded)m to group"
        } else {
            let km = distance / 1000
            return String(format: "%.1fkm to group", km)
        }
    }

    /// How spread out the group is
    var spreadDescription: String {
        if spreadRadius < 10 {
            return "Group is together"
        } else if spreadRadius < 50 {
            return "Group within \(Int(spreadRadius))m"
        } else if spreadRadius < 200 {
            return "Group spread over ~\(Int(spreadRadius))m"
        } else {
            return "Group is scattered"
        }
    }

    /// Combined accuracy is better than any individual
    var accuracyImprovement: String {
        if combinedAccuracy < 5 {
            return "High precision from group GPS"
        } else if combinedAccuracy < 15 {
            return "Good accuracy from \(memberCount) members"
        } else {
            return "Accuracy: ~\(Int(combinedAccuracy))m"
        }
    }
}

// MARK: - Equatable for Coordinate
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
