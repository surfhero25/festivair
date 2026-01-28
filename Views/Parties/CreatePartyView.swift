import SwiftUI
import MapKit

/// View for creating a new party
struct CreatePartyView: View {
    @EnvironmentObject var viewModel: PartiesViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Form State
    @State private var name = ""
    @State private var description = ""
    @State private var selectedVibe: PartyVibe = .chill
    @State private var selectedAccessType: PartyAccessType = .open
    @State private var startTime = Date()
    @State private var hasEndTime = false
    @State private var endTime = Date().addingTimeInterval(3600 * 4) // 4 hours later
    @State private var hasCapacity = false
    @State private var maxAttendees = 50
    @State private var locationName = ""

    // Location
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var showLocationPicker = false

    // UI State
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showVIPRequired = false

    private let subscriptionManager = SubscriptionManager.shared

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                basicInfoSection

                // Vibe Selection
                vibeSection

                // Access Type
                accessSection

                // Time
                timeSection

                // Location
                locationSection

                // Capacity
                capacitySection
            }
            .navigationTitle("Host a Party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        Task {
                            await createParty()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate || isCreating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("VIP Required", isPresented: $showVIPRequired) {
                Button("Upgrade", role: .cancel) {
                    // TODO: Show paywall
                }
                Button("Cancel", role: .destructive) {
                    selectedAccessType = .open
                }
            } message: {
                Text("Creating exclusive parties requires a VIP subscription.")
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView(selectedLocation: $selectedLocation, locationName: $locationName)
            }
            .overlay {
                if isCreating {
                    ProgressView("Creating party...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .loadingTimeout(isLoading: $isCreating, timeout: 30) {
                errorMessage = "Request timed out. Please try again."
                showError = true
            }
        }
    }

    // MARK: - Validation

    private var canCreate: Bool {
        !name.isEmpty && selectedLocation != nil
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        Section("Party Details") {
            TextField("Party Name", text: $name)

            TextField("Description (optional)", text: $description, axis: .vertical)
                .lineLimit(3...5)
        }
    }

    // MARK: - Vibe Section

    private var vibeSection: some View {
        Section("Vibe") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(PartyVibe.allCases, id: \.self) { vibe in
                    Button {
                        selectedVibe = vibe
                    } label: {
                        VStack(spacing: 4) {
                            Text(vibe.emoji)
                                .font(.title2)
                            Text(vibe.displayName)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedVibe == vibe ? Color.purple.opacity(0.2) : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedVibe == vibe ? Color.purple : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Access Section

    private var accessSection: some View {
        Section {
            Picker("Access Type", selection: $selectedAccessType) {
                ForEach(PartyAccessType.allCases, id: \.self) { access in
                    HStack {
                        Image(systemName: access.icon)
                        Text(access.displayName)
                        if access.requiresVIP {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .tag(access)
                }
            }
            .onChange(of: selectedAccessType) { _, newValue in
                if newValue.requiresVIP && !subscriptionManager.canHostExclusiveParties {
                    showVIPRequired = true
                }
            }
        } header: {
            Text("Access")
        } footer: {
            Text(accessFooter)
        }
    }

    private var accessFooter: String {
        switch selectedAccessType {
        case .open:
            return "Anyone can join your party"
        case .approval:
            return "You'll review and approve each guest"
        case .inviteOnly:
            return "Only people you invite can join"
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        Section("Time") {
            DatePicker("Start Time", selection: $startTime, in: Date()...)

            Toggle("Set End Time", isOn: $hasEndTime)

            if hasEndTime {
                DatePicker("End Time", selection: $endTime, in: startTime...)
            }
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        Section {
            Button {
                showLocationPicker = true
            } label: {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.purple)

                    if let location = selectedLocation {
                        VStack(alignment: .leading) {
                            Text(locationName.isEmpty ? "Location Set" : locationName)
                                .foregroundStyle(.primary)
                            Text("\(location.latitude, specifier: "%.4f"), \(location.longitude, specifier: "%.4f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Choose Location")
                            .foregroundStyle(.primary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Location")
        } footer: {
            if selectedAccessType != .open {
                Text("Location will be hidden until guests are approved")
            }
        }
    }

    // MARK: - Capacity Section

    private var capacitySection: some View {
        Section {
            Toggle("Limit Capacity", isOn: $hasCapacity)

            if hasCapacity {
                Stepper("Max: \(maxAttendees) people", value: $maxAttendees, in: 2...200, step: 5)
            }
        } header: {
            Text("Capacity")
        } footer: {
            Text("Leave unlimited or set a max number of guests")
        }
    }

    // MARK: - Create Party

    private func createParty() async {
        guard let location = selectedLocation else { return }

        isCreating = true

        // Get current user
        let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) ?? "Host"

        // Create a host user for the party
        let hostUser = User(displayName: displayName, avatarEmoji: "🎧")

        do {
            _ = try await viewModel.createParty(
                name: name,
                description: description.isEmpty ? nil : description,
                latitude: location.latitude,
                longitude: location.longitude,
                locationName: locationName.isEmpty ? nil : locationName,
                startTime: startTime,
                endTime: hasEndTime ? endTime : nil,
                maxAttendees: hasCapacity ? maxAttendees : nil,
                vibe: selectedVibe,
                accessType: selectedAccessType,
                hostUser: hostUser
            )

            isCreating = false
            dismiss()
        } catch {
            isCreating = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Location Picker View

struct LocationPickerView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var locationName: String
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isLoadingLocation = true
    @State private var locationError: String?
    @State private var hasInitializedMap = false

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoadingLocation && !hasInitializedMap {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Getting your location...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else if let error = locationError {
                    // Error state
                    VStack(spacing: 16) {
                        Image(systemName: "location.slash.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            locationError = nil
                            isLoadingLocation = true
                            initializeLocation()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    // Map view
                    Map(position: $cameraPosition) {
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        // Only update when user finishes dragging
                        selectedLocation = context.region.center
                    }

                    // Center pin indicator (always shows map center)
                    VStack {
                        Spacer()
                        Image(systemName: "mappin.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.purple)
                            .shadow(radius: 2)
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.caption)
                            .foregroundStyle(.purple)
                            .offset(y: -8)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Confirm") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedLocation == nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if hasInitializedMap && locationError == nil {
                    VStack(spacing: 12) {
                        TextField("Location Name (optional)", text: $locationName)
                            .textFieldStyle(.roundedBorder)

                        Text("Tap or drag the map to set location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
            .onAppear {
                initializeLocation()
            }
        }
    }

    private func initializeLocation() {
        let locationManager = appState.locationManager

        // Check authorization status first
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Request permission and wait for it
            locationManager.requestAuthorization()
            waitForAuthorization()

        case .denied, .restricted:
            locationError = "Location access denied.\nPlease enable location in Settings to choose a location on the map."
            isLoadingLocation = false

        case .authorizedWhenInUse, .authorizedAlways:
            // Permission granted, try to get location
            startLocationUpdates()

        @unknown default:
            locationError = "Unknown location authorization status"
            isLoadingLocation = false
        }
    }

    private func waitForAuthorization() {
        // Poll for authorization change (timeout after 10 seconds)
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak appState] timer in
            attempts += 1

            Task { @MainActor in
                guard let appState = appState else {
                    timer.invalidate()
                    return
                }

                let status = appState.locationManager.authorizationStatus

                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    timer.invalidate()
                    self.startLocationUpdates()
                } else if status == .denied || status == .restricted {
                    timer.invalidate()
                    self.locationError = "Location access denied.\nPlease enable location in Settings."
                    self.isLoadingLocation = false
                } else if attempts >= 20 { // 10 seconds timeout
                    timer.invalidate()
                    self.locationError = "Location permission request timed out.\nPlease try again."
                    self.isLoadingLocation = false
                }
            }
        }
    }

    private func startLocationUpdates() {
        let locationManager = appState.locationManager

        // Start location updates if not already running
        if !locationManager.isUpdating {
            locationManager.startUpdating()
        }

        // Wait for location with timeout
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            attempts += 1

            if let location = locationManager.currentLocation {
                timer.invalidate()
                let coordinate = CLLocationCoordinate2D(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                initializeMap(with: coordinate)
            } else if attempts >= 30 { // 9 seconds timeout
                timer.invalidate()
                self.locationError = "Could not get your location.\nPlease make sure Location Services are enabled and try again."
                self.isLoadingLocation = false
            }
        }
    }

    private func initializeMap(with coordinate: CLLocationCoordinate2D) {
        selectedLocation = coordinate
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))
        isLoadingLocation = false
        locationError = nil
        hasInitializedMap = true
    }
}

// MARK: - Preview

#Preview {
    CreatePartyView()
        .environmentObject(PartiesViewModel())
        .environmentObject(AppState())
}
