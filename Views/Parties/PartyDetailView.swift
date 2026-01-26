import SwiftUI
import MapKit

/// Detail view for a party
struct PartyDetailView: View {
    let party: Party
    @EnvironmentObject var viewModel: PartiesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showHostProfile = false
    @State private var isJoining = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var userAttendeeStatus: AttendeeStatus?

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId)
    }

    private var isHost: Bool {
        currentUserId == party.hostUserId
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Info Cards
                    infoSection

                    // Location (if visible)
                    if !party.isLocationHidden || isHost || userAttendeeStatus == .approved || userAttendeeStatus == .attending {
                        locationSection
                    } else if party.isExclusive {
                        hiddenLocationSection
                    }

                    // Attendees Preview
                    attendeesSection

                    // Action Button
                    actionSection
                }
                .padding()
            }
            .navigationTitle(party.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Vibe Badge
            HStack {
                Text(party.vibe.emoji)
                    .font(.system(size: 50))

                VStack(alignment: .leading) {
                    Text(party.vibe.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    if party.isHappeningNow {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("Happening Now")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text(party.formattedTime)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Access Type
                VStack {
                    Image(systemName: party.accessType.icon)
                        .font(.title2)
                    Text(party.accessType.displayName)
                        .font(.caption2)
                }
                .foregroundStyle(party.isExclusive ? .orange : .green)
            }

            // Host Info
            Button {
                showHostProfile = true
            } label: {
                HStack {
                    Text("Hosted by")
                        .foregroundStyle(.secondary)
                    Text(party.hostDisplayName)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let description = party.partyDescription {
                Text(description)
                    .font(.body)
            }

            HStack(spacing: 16) {
                // Time
                infoItem(
                    icon: "clock.fill",
                    title: "Time",
                    value: party.formattedTime
                )

                // Capacity
                if let max = party.maxAttendees {
                    infoItem(
                        icon: "person.2.fill",
                        title: "Capacity",
                        value: "\(party.currentAttendeeCount)/\(max)"
                    )
                }

                // Spots
                if let spots = party.spotsRemaining {
                    infoItem(
                        icon: "ticket.fill",
                        title: "Spots",
                        value: spots > 0 ? "\(spots) left" : "Full"
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func infoItem(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.purple)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Location Section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.purple)
                Text("Location")
                    .font(.headline)
                Spacer()
                if let name = party.locationName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: party.latitude, longitude: party.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Marker(party.name, coordinate: CLLocationCoordinate2D(
                    latitude: party.latitude,
                    longitude: party.longitude
                ))
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Open in Maps
            Button {
                openInMaps()
            } label: {
                Label("Open in Maps", systemImage: "arrow.up.right.square")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var hiddenLocationSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title)
                .foregroundStyle(.orange)

            Text("Location Hidden")
                .font(.headline)

            Text("Get approved to see the exact location")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Attendees Section

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attendees")
                    .font(.headline)
                Spacer()
                Text("\(party.currentAttendeeCount)")
                    .foregroundStyle(.secondary)
            }

            // Placeholder for attendee avatars
            HStack(spacing: -10) {
                ForEach(0..<min(5, party.currentAttendeeCount), id: \.self) { _ in
                    Circle()
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle().stroke(.white, lineWidth: 2)
                        )
                }
                if party.currentAttendeeCount > 5 {
                    Text("+\(party.currentAttendeeCount - 5)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Action Section

    private var actionSection: some View {
        Group {
            if isHost {
                // Host actions
                VStack(spacing: 12) {
                    Button(role: .destructive) {
                        Task {
                            try? await viewModel.endParty(party)
                            dismiss()
                        }
                    } label: {
                        Label("End Party", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                // Guest actions
                joinButton
            }
        }
    }

    private var joinButton: some View {
        Button {
            Task {
                await joinParty()
            }
        } label: {
            HStack {
                if isJoining {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: buttonIcon)
                    Text(buttonText)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(buttonColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isJoining || party.isFull || userAttendeeStatus == .attending)
    }

    private var buttonText: String {
        switch userAttendeeStatus {
        case .requested: return "Request Pending"
        case .approved: return "Confirm Attendance"
        case .attending: return "You're Going!"
        case .declined: return "Request Declined"
        default:
            return party.isExclusive ? "Request to Join" : "I'm Going"
        }
    }

    private var buttonIcon: String {
        switch userAttendeeStatus {
        case .requested: return "clock.fill"
        case .approved, .attending: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        default:
            return party.isExclusive ? "hand.raised.fill" : "party.popper.fill"
        }
    }

    private var buttonColor: Color {
        switch userAttendeeStatus {
        case .requested: return .orange
        case .attending: return .green
        case .declined: return .red
        default: return .purple
        }
    }

    // MARK: - Actions

    private func joinParty() async {
        // TODO: Get current user from context
        isJoining = true

        // For now, create a mock user
        let mockUser = User(displayName: "Test User", avatarEmoji: "🎧")

        do {
            try await viewModel.requestToJoin(party: party, user: mockUser)
            userAttendeeStatus = party.accessType == .open ? .attending : .requested
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isJoining = false
    }

    private func openInMaps() {
        let coordinate = CLLocationCoordinate2D(latitude: party.latitude, longitude: party.longitude)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = party.name
        mapItem.openInMaps()
    }
}

// MARK: - Preview

#Preview {
    let party = Party(
        name: "Rooftop Vibes",
        hostUserId: "123",
        hostDisplayName: "DJ Sparkle",
        description: "Chill rooftop party with amazing views and great music",
        latitude: Constants.DefaultLocation.latitude,
        longitude: Constants.DefaultLocation.longitude,
        locationName: "Downtown LA",
        startTime: Date(),
        maxAttendees: 50,
        vibe: .rooftop,
        accessType: .approval
    )
    party.currentAttendeeCount = 12

    return PartyDetailView(party: party)
        .environmentObject(PartiesViewModel())
}
