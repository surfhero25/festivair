import SwiftUI
import MapKit

/// Main view for party discovery - shown as a tab
struct PartiesView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = PartiesViewModel()

    @State private var showMapView = false
    @State private var showCreateParty = false
    @State private var showHostDashboard = false
    @State private var selectedParty: Party?
    @State private var showFilters = false

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                if showMapView {
                    partyMapView
                } else {
                    partyListView
                }

                // FAB - Create Party
                createPartyButton
            }
            .navigationTitle("Parties")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("View", selection: $showMapView) {
                        Image(systemName: "list.bullet").tag(false)
                        Image(systemName: "map").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // Filters
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: viewModel.selectedVibe != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }

                        // Host Dashboard (if hosting any parties)
                        if !viewModel.myHostedParties.isEmpty {
                            Button {
                                showHostDashboard = true
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                    if !viewModel.pendingRequests.isEmpty {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 2, y: -2)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateParty) {
                CreatePartyView()
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $showHostDashboard) {
                HostDashboardView()
                    .environmentObject(viewModel)
            }
            .sheet(item: $selectedParty) { party in
                if party.isExclusive && !isVIP {
                    // Non-VIP tapped a locked exclusive party → show paywall
                    PaywallView()
                } else {
                    PartyDetailView(party: party)
                        .environmentObject(viewModel)
                }
            }
            .sheet(isPresented: $showFilters) {
                filterSheet
            }
            .task {
                viewModel.configure(modelContext: modelContext)
                await loadParties()
            }
        }
    }

    // MARK: - List View

    private var partyListView: some View {
        Group {
            if viewModel.isLoading && viewModel.nearbyParties.isEmpty {
                ProgressView("Finding parties...")
            } else if viewModel.nearbyParties.isEmpty {
                emptyState
            } else {
                List {
                    // Happening Now
                    let happeningNow = viewModel.nearbyParties.filter { $0.isHappeningNow }
                    if !happeningNow.isEmpty {
                        Section("Happening Now") {
                            ForEach(happeningNow) { party in
                                PartyRowView(party: party) {
                                    selectedParty = party
                                }
                            }
                        }
                    }

                    // Coming Up
                    let upcoming = viewModel.nearbyParties.filter { !$0.isHappeningNow && $0.timeUntilStart > 0 }
                    if !upcoming.isEmpty {
                        Section("Coming Up") {
                            ForEach(upcoming) { party in
                                PartyRowView(party: party) {
                                    selectedParty = party
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    await loadParties()
                }
            }
        }
    }

    // MARK: - Map View

    private var isVIP: Bool {
        SubscriptionManager.shared.canHostExclusiveParties
    }

    private var partyMapView: some View {
        Map {
            ForEach(viewModel.nearbyParties) { party in
                // Only show pins for parties with visible locations
                // Open parties: always visible
                // Exclusive parties: location hidden until approved (isLocationHidden=true by default)
                // Even VIP users can't see invite-only locations unless they're approved
                if !party.isLocationHidden {
                    Annotation(party.name, coordinate: CLLocationCoordinate2D(
                        latitude: party.latitude,
                        longitude: party.longitude
                    )) {
                        Button {
                            selectedParty = party
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: party.vibe.icon)
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(party.isHappeningNow ? Color.purple : Color.gray)
                                    .clipShape(Circle())

                                Text(party.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No parties nearby")
                .font(.headline)

            Text("Tap + to host the first one")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Create Party Button

    private var createPartyButton: some View {
        Button {
            showCreateParty = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.purple)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .padding()
    }

    // MARK: - Filters

    private var filterSheet: some View {
        NavigationStack {
            List {
                Section("Vibe") {
                    ForEach(PartyVibe.allCases, id: \.self) { vibe in
                        Button {
                            if viewModel.selectedVibe == vibe {
                                viewModel.selectedVibe = nil
                            } else {
                                viewModel.selectedVibe = vibe
                            }
                        } label: {
                            HStack {
                                Image(systemName: vibe.icon)
                                Text(vibe.displayName)
                                Spacer()
                                if viewModel.selectedVibe == vibe {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Access") {
                    // Non-VIP users can only filter by open parties
                    // Showing approval/inviteOnly filters would imply details they can't access
                    ForEach(PartyAccessType.allCases.filter { !$0.requiresVIP || isVIP }, id: \.self) { access in
                        Button {
                            if viewModel.selectedAccessType == access {
                                viewModel.selectedAccessType = nil
                            } else {
                                viewModel.selectedAccessType = access
                            }
                        } label: {
                            HStack {
                                Image(systemName: access.icon)
                                Text(access.displayName)
                                Spacer()
                                if viewModel.selectedAccessType == access {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    Toggle("Active parties only", isOn: $viewModel.showActiveOnly)
                }

                Section {
                    Button("Clear Filters") {
                        viewModel.clearFilters()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showFilters = false
                        viewModel.applyFilters()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Load Data

    private func loadParties() async {
        guard let userId = currentUserId else { return }

        // Get current location
        let location = appState.locationManager.currentLocation
        let lat = location?.latitude ?? Constants.DefaultLocation.latitude
        let lon = location?.longitude ?? Constants.DefaultLocation.longitude

        await viewModel.fetchNearbyParties(latitude: lat, longitude: lon)
        await viewModel.fetchMyHostedParties(userId: userId)
        await viewModel.fetchPendingRequests(hostUserId: userId)
    }
}

// MARK: - Party Row View

struct PartyRowView: View {
    let party: Party
    let onTap: () -> Void

    private var isVIP: Bool {
        SubscriptionManager.shared.canHostExclusiveParties
    }

    /// Non-VIP users see a locked teaser for exclusive parties
    private var isLocked: Bool {
        party.isExclusive && !isVIP
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Vibe icon
                Image(systemName: party.vibe.icon)
                    .font(.title2)
                    .foregroundStyle(isLocked ? .orange : .purple)
                    .frame(width: 50, height: 50)
                    .background(isLocked ? Color.orange.opacity(0.2) : Color.purple.opacity(0.2))
                    .clipShape(Circle())

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(party.name)
                            .font(.headline)

                        if party.isExclusive {
                            HStack(spacing: 2) {
                                Image(systemName: "crown.fill")
                                    .font(.caption2)
                                Text("VIP")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }

                    if isLocked {
                        // Teaser — no host name, no location, no time details
                        Text("Upgrade to VIP to see details")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Hosted by \(party.hostDisplayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Label(party.formattedTime, systemImage: "clock")
                            if let location = party.locationName {
                                Label(location, systemImage: "mappin")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Status
                VStack(alignment: .trailing, spacing: 4) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    } else {
                        if party.isHappeningNow {
                            Text("LIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red)
                                .clipShape(Capsule())
                        }

                        Text("\(party.currentAttendeeCount) attending")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let spots = party.spotsRemaining, spots > 0 {
                            Text("\(spots) spots left")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else if party.isFull {
                            Text("FULL")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    PartiesView()
        .environmentObject(AppState())
}
