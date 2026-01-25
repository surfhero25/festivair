import SwiftUI
import MapKit

struct SquadMapView: View {
    @EnvironmentObject var appState: AppState
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showMemberList = false
    @State private var showJoinSquad = false
    @State private var isFindMeActive = false

    private var mapViewModel: MapViewModel {
        appState.mapViewModel
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
                                accuracyQuality: member.accuracyQuality
                            )
                            .onTapGesture {
                                mapViewModel.centerOnMember(member)
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
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }

                // Floating UI
                VStack {
                    // Connection status bar
                    ConnectionStatusBar()
                        .padding(.horizontal)

                    Spacer()

                    // Group centroid info card (if available)
                    if let centroid = mapViewModel.groupCentroid {
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

                        // Find Group button (collaborative GPS)
                        Button {
                            mapViewModel.centerOnGroup()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "person.3.sequence.fill")
                                    .font(.title2)
                                Text("Find Group")
                                    .font(.caption)
                            }
                            .foregroundStyle(mapViewModel.groupCentroid != nil ? .purple : .secondary)
                            .frame(width: 80, height: 60)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(mapViewModel.groupCentroid == nil)

                        Spacer()

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
                MemberListView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showJoinSquad) {
                JoinSquadView()
            }
        }
    }

    private func activateFindMe() {
        isFindMeActive = true
        mapViewModel.activateFindMe()

        // Reset UI state after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            isFindMeActive = false
        }
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

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                Text(emoji)
                    .font(.title)
                    .padding(8)
                    .background(isOnline ? Color.purple : Color.gray)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.white, lineWidth: 2)
                    )

                // GPS accuracy indicator dot
                if isOnline {
                    Circle()
                        .fill(accuracyQuality.color)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 1)
                        )
                        .offset(x: 2, y: 2)
                }
            }

            VStack(spacing: 1) {
                Text(name)
                    .font(.caption2)
                    .fontWeight(.medium)

                if let distance = distanceText {
                    Text(distance)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
