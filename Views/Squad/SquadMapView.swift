import SwiftUI
import MapKit
import CoreLocation

struct SquadMapView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var offlineMapService = OfflineMapService.shared
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showMemberList = false
    @State private var showJoinSquad = false
    @State private var isFindMeActive = false
    @State private var showFullCompass = false
    @State private var showStatusPicker = false
    @State private var showPinSheet = false
    @State private var pinDropCoordinate: CLLocationCoordinate2D?
    @State private var selectedPinForDetail: MeetupPin?

    // Facility state
    @State private var selectedFacilityTypes: Set<FacilityType> = Set(FacilityType.quickAccess)
    @State private var selectedFacility: Facility?
    @State private var showFacilityFilters = false

    private var mapViewModel: MapViewModel {
        appState.mapViewModel
    }

    private var currentUserStatus: UserStatus? {
        UserDefaults.standard.codable(forKey: "FestivAir.CurrentUserStatus")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Map
                Map(position: $position) {
                    UserAnnotation()

                    // Squad member annotations with distance
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

                    // Group centroid annotation (collaborative GPS)
                    if let centroid = mapViewModel.groupCentroid {
                        Annotation("Squad Center", coordinate: centroid.coordinate) {
                            GroupCentroidView(centroid: centroid)
                                .onTapGesture {
                                    mapViewModel.centerOnGroup()
                                }
                        }
                    }

                    // Meetup pins
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

                    // Facility annotations
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
                .onMapCameraChange { context in
                    // Store camera region for pin dropping
                }
                .onLongPressGesture(minimumDuration: 0.5) { screenPosition in
                    // Long press to drop pin - handled via gesture below
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

                    // Bottom controls
                    HStack(spacing: 12) {
                        // Find Me button
                        Button {
                            activateFindMe()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: isFindMeActive ? "antenna.radiowaves.left.and.right" : "dot.radiowaves.left.and.right")
                                    .font(.title2)
                                Text("Find Me")
                                    .font(.caption)
                            }
                            .foregroundStyle(isFindMeActive ? .purple : .primary)
                            .frame(width: 70, height: 60)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // Status button
                        Button {
                            showStatusPicker = true
                        } label: {
                            VStack(spacing: 4) {
                                if let status = currentUserStatus, status.isActive {
                                    Text(status.emoji)
                                        .font(.title2)
                                } else {
                                    Image(systemName: "bubble.left.fill")
                                        .font(.title2)
                                }
                                Text("Status")
                                    .font(.caption)
                            }
                            .foregroundStyle(currentUserStatus?.isActive == true ? .purple : .primary)
                            .frame(width: 70, height: 60)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // Meet Here button (drop pin at current location)
                        Button {
                            dropPinAtCurrentLocation()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.title2)
                                Text("Meet Here")
                                    .font(.caption)
                            }
                            .foregroundStyle(.orange)
                            .frame(width: 80, height: 60)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // Facilities toggle button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFacilityFilters.toggle()
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: showFacilityFilters ? "building.2.fill" : "building.2")
                                    .font(.title2)
                                Text("Facilities")
                                    .font(.caption)
                            }
                            .foregroundStyle(showFacilityFilters ? .purple : .primary)
                            .frame(width: 80, height: 60)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Spacer()

                        // Find Group button (collaborative GPS)
                        Button {
                            mapViewModel.centerOnGroup()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "person.3.sequence.fill")
                                    .font(.title2)
                                Text("Group")
                                    .font(.caption)
                            }
                            .foregroundStyle(mapViewModel.groupCentroid != nil ? .purple : .secondary)
                            .frame(width: 70, height: 60)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(mapViewModel.groupCentroid == nil)

                        // Member list button
                        Button {
                            showMemberList = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "person.3.fill")
                                    .font(.title2)
                                Text("Squad")
                                    .font(.caption)
                            }
                            .foregroundStyle(.primary)
                            .frame(width: 70, height: 60)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding()
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
            .sheet(isPresented: $showPinSheet) {
                if let coordinate = pinDropCoordinate {
                    MeetupPinSheet(coordinate: coordinate) { pin in
                        mapViewModel.dropPin(pin)
                    }
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
            return
        }

        pinDropCoordinate = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        showPinSheet = true
    }

    private func distanceToFacility(_ facility: Facility) -> Double? {
        guard let location = appState.locationManager.currentLocation else { return nil }
        let userLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let facilityLoc = CLLocation(latitude: facility.latitude, longitude: facility.longitude)
        return userLoc.distance(from: facilityLoc)
    }
}

// MARK: - Connection Status Bar
struct ConnectionStatusBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Mesh status
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.meshManager.connectedPeers.isEmpty ? .orange : .green)
                    .frame(width: 8, height: 8)
                Text("\(appState.meshManager.connectedPeers.count) connected")
                    .font(.caption)
            }

            Spacer()

            // Gateway status
            if appState.gatewayManager.isGateway {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                    Text("Gateway")
                        .font(.caption)
                }
                .foregroundStyle(.purple)
            }

            // Battery
            HStack(spacing: 4) {
                Image(systemName: batteryIcon)
                    .font(.caption)
                Text("\(appState.gatewayManager.batteryLevel)%")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var batteryIcon: String {
        let level = appState.gatewayManager.batteryLevel
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }
}

// MARK: - Member Annotation View
struct MemberAnnotationView: View {
    let emoji: String
    let name: String
    let isOnline: Bool
    var distanceText: String? = nil
    var accuracyQuality: MemberAnnotation.AccuracyQuality = .unknown
    var isNavigationTarget: Bool = false
    var status: UserStatus? = nil

    @State private var pulseAnimation = false

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

                Text(emoji)
                    .font(.title)
                    .padding(8)
                    .background(isNavigationTarget ? Color.green : (isOnline ? Color.purple : Color.gray))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isNavigationTarget ? Color.green : .white, lineWidth: isNavigationTarget ? 3 : 2)
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

#Preview {
    SquadMapView()
        .environmentObject(AppState())
}
