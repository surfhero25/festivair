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
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var locationName: String
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    if let location = selectedLocation {
                        Marker("Party Location", coordinate: location)
                    }
                }
                .onTapGesture { position in
                    // Note: This doesn't work directly in SwiftUI Maps
                    // Would need MapReader for proper coordinate conversion
                }

                // Center pin
                VStack {
                    Spacer()
                    Image(systemName: "mappin")
                        .font(.title)
                        .foregroundStyle(.purple)
                    Spacer()
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
                        // Use current map center as location
                        // For now, use a default
                        if selectedLocation == nil {
                            selectedLocation = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    TextField("Location Name (optional)", text: $locationName)
                        .textFieldStyle(.roundedBorder)

                    Text("Drag the map to position the pin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CreatePartyView()
        .environmentObject(PartiesViewModel())
        .environmentObject(AppState())
}
