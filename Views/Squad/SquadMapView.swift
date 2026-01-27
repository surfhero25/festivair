import SwiftUI
import MapKit
import CoreLocation

struct SquadMapView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        SquadMapContentView(mapViewModel: appState.mapViewModel)
    }
}

// MARK: - Squad Map Content (properly observes MapViewModel)
private struct SquadMapContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var mapViewModel: MapViewModel
    @ObservedObject var offlineMapService = OfflineMapService.shared
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showMemberList = false
    @State private var showJoinSquad = false
    @State private var isFindMeActive = false
    @State private var showFullCompass = false
    @State private var showStatusPicker = false
    @State private var pinDropLocation: IdentifiableCoordinate?
    @State private var selectedPinForDetail: MeetupPin?

    // Facility state
    @State private var selectedFacilityTypes: Set<FacilityType> = Set(FacilityType.quickAccess)
    @State private var selectedFacility: Facility?
    @State private var showFacilityFilters = false
    @State private var showLocationError = false

    private var currentUserStatus: UserStatus? {
        UserDefaults.standard.codable(forKey: "FestivAir.CurrentUserStatus")
    }

    // MARK: - Map Content Builders
    // Extracted to help Swift type-checker with complex view body

    @MapContentBuilder
    private var memberAnnotations: some MapContent {
        ForEach(mapViewModel.memberAnnotations) { member in
            Annotation(member.displayName, coordinate: member.coordinate) {
                MemberAnnotationView(
                    emoji: member.emoji,
                    name: member.displayName,
                    isOnline: member.isOnline,
                    distanceText: member.distanceText,
                    accuracyQuality: member.accuracyQuality,
                    isNavigationTarget: mapViewModel.navigationTarget?.id == member.id,
                    status: member.status
                )
                .onTapGesture {
                    mapViewModel.centerOnMember(member)
                }
                .contextMenu {
                    Button {
                        Haptics.medium()
                        mapViewModel.startNavigatingTo(member)
                    } label: {
                        Label("Navigate to \(member.displayName)", systemImage: "location.north.fill")
                    }

                    Button {
                        mapViewModel.centerOnMember(member)
                    } label: {
                        Label("Center on Map", systemImage: "scope")
                    }
                }
            }
        }
    }

    @MapContentBuilder
    private var pinAnnotations: some MapContent {
        ForEach(mapViewModel.activeMeetupPins) { pin in
            Annotation(pin.name, coordinate: pin.coordinate) {
                MeetupPinAnnotationView(
                    pin: pin,
                    isSelected: mapViewModel.selectedPin?.id == pin.id,
                    onTap: {
                        selectedPinForDetail = pin
                    },
                    onNavigate: {
                        mapViewModel.navigateToPin(pin)
                    },
                    onDismiss: {
                        mapViewModel.dismissPin(pin)
                    }
                )
            }
        }
    }

    @MapContentBuilder
    private var facilityAnnotations: some MapContent {
        ForEach(visibleFacilities) { facility in
            Annotation(facility.name, coordinate: facility.coordinate) {
                FacilityAnnotationView(
                    facility: facility,
                    isSelected: selectedFacility?.id == facility.id,
                    onTap: {
                        selectedFacility = facility
                    }
                )
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Map
                Map(position: $position) {
                    UserAnnotation()

                    // Squad member annotations (extracted to help compiler)
                    memberAnnotations

                    // Group centroid annotation (collaborative GPS)
                    if let centroid = mapViewModel.groupCentroid {
                        Annotation("Squad Center", coordinate: centroid.coordinate) {
                            GroupCentroidView(centroid: centroid)
                                .onTapGesture {
                                    mapViewModel.centerOnGroup()
                                }
                        }
                    }

                    // Meetup pins (extracted)
                    pinAnnotations

                    // Facility annotations (extracted)
                    facilityAnnotations
                }
                .onMapCameraChange { _ in
                    // Store camera region for pin dropping
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    // Long press to drop pin at current location
                    dropPinAtCurrentLocation()
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }

                // Floating UI
                VStack(spacing: 0) {
                    // Connection status bar
                    ConnectionStatusBar()
                        .padding(.horizontal)

                    // Facility filter bar (collapsible)
                    if showFacilityFilters {
                        VStack(spacing: 0) {
                            FacilityFilterBar(
                                selectedTypes: $selectedFacilityTypes,
                                onFilterChange: nil
                            )

                            // Quick nearest facility row
                            if let userLocation = appState.locationManager.currentLocation {
                                NearestFacilityView(
                                    userLocation: CLLocationCoordinate2D(
                                        latitude: userLocation.latitude,
                                        longitude: userLocation.longitude
                                    ),
                                    onNavigate: { facility in
                                        selectedFacility = facility
                                    }
                                )
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Compact compass when navigating (if not expanded)
                    if mapViewModel.isNavigating,
                       let target = mapViewModel.navigationTarget,
                       !showFullCompass {
                        CompactCompassView(
                            targetName: target.displayName,
                            bearing: mapViewModel.bearingToTarget,
                            distance: mapViewModel.proximityManager.currentDistance,
                            proximityLevel: mapViewModel.proximityManager.proximityLevel,
                            onTap: { showFullCompass = true },
                            onDismiss: { mapViewModel.stopNavigating() }
                        )
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()

                    // Group centroid info card (if available and not navigating)
                    if let centroid = mapViewModel.groupCentroid, !mapViewModel.isNavigating {
                        GroupInfoCard(centroid: centroid) {
                            mapViewModel.centerOnGroup()
                        }
                        .padding(.horizontal)
                    }

                    // Bottom controls - simplified row
                    HStack(spacing: 12) {
                        // Meet Here button
                        MapControlButton(
                            icon: "mappin.and.ellipse",
                            label: "Meet",
                            tint: .orange
                        ) {
                            dropPinAtCurrentLocation()
                        }

                        // Facilities toggle
                        MapControlButton(
                            icon: showFacilityFilters ? "building.2.fill" : "building.2",
                            label: "Places",
                            isActive: showFacilityFilters
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFacilityFilters.toggle()
                            }
                        }

                        // Status button
                        MapControlButton(
                            icon: "face.smiling",
                            label: "Status"
                        ) {
                            showStatusPicker = true
                        }

                        // Squad list button
                        MapControlButton(
                            icon: "person.3.fill",
                            label: "Squad"
                        ) {
                            showMemberList = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
            }
            .navigationTitle("Squad Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showJoinSquad = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showMemberList) {
                MemberListView { peer in
                    // Convert peer to member annotation and start navigation
                    if let member = mapViewModel.memberAnnotations.first(where: { $0.id == peer.id }) {
                        mapViewModel.startNavigatingTo(member)
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showJoinSquad) {
                JoinSquadView()
            }
            .sheet(isPresented: $showFullCompass) {
                if let target = mapViewModel.navigationTarget {
                    CompassArrowView(
                        targetName: target.displayName,
                        targetEmoji: target.emoji,
                        bearing: mapViewModel.bearingToTarget,
                        distance: mapViewModel.proximityManager.currentDistance,
                        proximityLevel: mapViewModel.proximityManager.proximityLevel,
                        onDismiss: {
                            showFullCompass = false
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: mapViewModel.memberAnnotations) { _, _ in
                // Update navigation target when member locations change
                if mapViewModel.isNavigating {
                    mapViewModel.updateNavigationTarget()
                }
            }
            .sheet(isPresented: $showStatusPicker) {
                StatusPickerView()
            }
            .sheet(item: $pinDropLocation) { location in
                MeetupPinSheet(coordinate: location.coordinate) { pin in
                    mapViewModel.dropPin(pin)
                }
            }
            .sheet(item: $selectedPinForDetail) { pin in
                MeetupPinDetailSheet(
                    pin: pin,
                    distance: mapViewModel.distanceToPin(pin),
                    onNavigate: {
                        mapViewModel.navigateToPin(pin)
                    },
                    onDismiss: {
                        mapViewModel.dismissPin(pin)
                    }
                )
            }
            .sheet(item: $selectedFacility) { facility in
                FacilityDetailSheet(
                    facility: facility,
                    distance: distanceToFacility(facility),
                    onNavigate: {
                        // Navigate to facility using map
                        if let location = appState.locationManager.currentLocation {
                            let url = URL(string: "maps://?saddr=\(location.latitude),\(location.longitude)&daddr=\(facility.latitude),\(facility.longitude)")
                            if let url = url {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                )
            }
            .alert("Location Not Available", isPresented: $showLocationError) {
                Button("OK") {}
            } message: {
                Text("Waiting for GPS. Make sure location services are enabled and try again.")
            }
        }
    }

    // MARK: - Computed Properties

    private var visibleFacilities: [Facility] {
        guard !selectedFacilityTypes.isEmpty else { return [] }
        return offlineMapService.facilitiesForCurrentVenue
            .filter { selectedFacilityTypes.contains($0.type) }
    }

    private func activateFindMe() {
        isFindMeActive = true
        mapViewModel.activateFindMe()

        // Reset UI state after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            isFindMeActive = false
        }
    }

    private func dropPinAtCurrentLocation() {
        guard let location = appState.locationManager.currentLocation else {
            Haptics.error()
            showLocationError = true
            return
        }

        pinDropLocation = IdentifiableCoordinate(
            coordinate: CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )
        )
    }

    private func distanceToFacility(_ facility: Facility) -> Double? {
        guard let location = appState.locationManager.currentLocation else { return nil }
        let userLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let facilityLoc = CLLocation(latitude: facility.latitude, longitude: facility.longitude)
        return userLoc.distance(from: facilityLoc)
    }
}

// MARK: - Map Control Button
struct MapControlButton: View {
    let icon: String?
    let label: String
    var tint: Color = .purple
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.title3)
                }
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isDisabled ? .secondary : (isActive ? tint : .primary))
            .frame(width: 56, height: 52)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isDisabled)
    }
}

// MARK: - Connection Status Bar
struct ConnectionStatusBar: View {
    @EnvironmentObject var appState: AppState

    private var noConnectivity: Bool {
        !appState.gatewayManager.hasInternetAccess
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // Mesh peers connected
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.meshManager.connectedPeers.isEmpty ? .orange : .green)
                        .frame(width: 6, height: 6)
                    Text("\(appState.meshManager.connectedPeers.count) nearby")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6).opacity(0.8))
                .clipShape(Capsule())

                Spacer()

                // Gateway status (only show if we're the gateway)
                if appState.gatewayManager.isGateway {
                    HStack(spacing: 3) {
                        Image(systemName: "wifi")
                            .font(.caption2)
                        Text("Syncing")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            // Airplane mode / no connectivity tip
            if noConnectivity {
                HStack(spacing: 6) {
                    Image(systemName: "airplane")
                        .font(.caption2)
                    Text("No connection. Turn on Bluetooth & Wi-Fi to find your squad.")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Member Annotation View
struct MemberAnnotationView: View {
    let emoji: String // Kept for backward compatibility but not used
    let name: String
    let isOnline: Bool
    var distanceText: String? = nil
    var accuracyQuality: MemberAnnotation.AccuracyQuality = .unknown
    var isNavigationTarget: Bool = false
    var status: UserStatus? = nil
    var profileAssetId: String? = nil

    @State private var pulseAnimation = false

    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                // Pulse ring for navigation target
                if isNavigationTarget {
                    Circle()
                        .stroke(Color.purple.opacity(pulseAnimation ? 0.0 : 0.6), lineWidth: 3)
                        .frame(width: pulseAnimation ? 70 : 50, height: pulseAnimation ? 70 : 50)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulseAnimation)
                }

                // Profile photo or initials
                ProfilePhotoView(
                    assetId: profileAssetId,
                    displayName: name,
                    size: 44,
                    isOnline: isOnline,
                    tintColor: isNavigationTarget ? .green : .purple
                )

                // GPS accuracy indicator dot
                if isOnline && !isNavigationTarget {
                    Circle()
                        .fill(accuracyQuality.color)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 1)
                        )
                        .offset(x: 2, y: 2)
                }

                // Navigation indicator
                if isNavigationTarget {
                    Image(systemName: "location.north.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.green)
                        .clipShape(Circle())
                        .offset(x: 2, y: 2)
                }
            }

            VStack(spacing: 1) {
                Text(name)
                    .font(.caption2)
                    .fontWeight(.medium)

                // Status badge (if available)
                if let status = status, status.isActive {
                    StatusBadgeView(status: status, compact: true)
                } else if let distance = distanceText {
                    Text(distance)
                        .font(.caption2)
                        .foregroundStyle(isNavigationTarget ? .green : .secondary)
                        .fontWeight(isNavigationTarget ? .semibold : .regular)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .onAppear {
            if isNavigationTarget {
                pulseAnimation = true
            }
        }
        .onChange(of: isNavigationTarget) { _, isTarget in
            pulseAnimation = isTarget
        }
    }
}

// MARK: - Group Centroid View (Map Annotation)
struct GroupCentroidView: View {
    let centroid: GroupCentroid

    var body: some View {
        VStack(spacing: 2) {
            // Pulsing group marker
            ZStack {
                // Spread radius indicator
                Circle()
                    .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                    .frame(width: 60, height: 60)

                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: "person.3.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
            }

            VStack(spacing: 1) {
                Text("Squad Center")
                    .font(.caption2)
                    .fontWeight(.semibold)

                if let distance = centroid.distanceText {
                    Text(distance)
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Group Info Card
struct GroupInfoCard: View {
    let centroid: GroupCentroid
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: "location.viewfinder")
                        .font(.title3)
                        .foregroundStyle(.purple)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(centroid.spreadDescription)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        if let distance = centroid.distanceText {
                            Text(distance)
                                .font(.subheadline)
                                .foregroundStyle(.purple)
                                .fontWeight(.semibold)
                        }
                    }

                    Text(centroid.accuracyImprovement)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Identifiable Coordinate Wrapper
struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    SquadMapView()
        .environmentObject(AppState())
}
