import SwiftUI

/// Dashboard for hosts to manage party requests
struct HostDashboardView: View {
    @EnvironmentObject var viewModel: PartiesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedParty: Party?

    var body: some View {
        NavigationStack {
            List {
                // Pending Requests
                if !viewModel.pendingRequests.isEmpty {
                    Section {
                        ForEach(viewModel.pendingRequests) { request in
                            RequestRowView(
                                attendee: request,
                                onApprove: {
                                    Task {
                                        await approveRequest(request)
                                    }
                                },
                                onDecline: {
                                    Task {
                                        await declineRequest(request)
                                    }
                                }
                            )
                        }
                    } header: {
                        HStack {
                            Text("Pending Requests")
                            Spacer()
                            Text("\(viewModel.pendingRequests.count)")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // My Hosted Parties
                Section("My Parties") {
                    if viewModel.myHostedParties.isEmpty {
                        Text("You haven't hosted any parties yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.myHostedParties) { party in
                            HostedPartyRowView(party: party)
                        }
                    }
                }
            }
            .navigationTitle("Host Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if viewModel.pendingRequests.isEmpty && viewModel.myHostedParties.isEmpty {
                    emptyState
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No pending requests")
                .font(.headline)

            Text("Requests from guests will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func approveRequest(_ attendee: PartyAttendee) async {
        // Find the party
        guard let party = viewModel.myHostedParties.first(where: { $0.id == attendee.partyId }) else {
            return
        }

        do {
            try await viewModel.approveRequest(attendee, party: party)
        } catch {
            print("Failed to approve: \(error)")
        }
    }

    private func declineRequest(_ attendee: PartyAttendee) async {
        do {
            try await viewModel.declineRequest(attendee)
        } catch {
            print("Failed to decline: \(error)")
        }
    }
}

// MARK: - Request Row View

struct RequestRowView: View {
    let attendee: PartyAttendee
    let onApprove: () -> Void
    let onDecline: () -> Void

    @State private var showProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User Info
            HStack(spacing: 12) {
                // Avatar
                ProfilePhotoView(
                    assetId: attendee.profilePhotoAssetId,
                    emoji: attendee.emoji,
                    size: 50,
                    isOnline: true
                )

                // Name & Stats
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(attendee.displayName)
                            .fontWeight(.semibold)

                        // Verification badge
                        if let verification = attendee.verification, verification != .none {
                            Image(systemName: verification.badgeIcon)
                                .font(.caption)
                                .foregroundStyle(verificationColor(for: verification))
                        }
                    }

                    // Followers
                    if let followers = attendee.formattedFollowers {
                        Text("\(followers) followers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Request time
                    Text("Requested \(attendee.requestedAt.timeAgo)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // View Profile
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "person.circle")
                        .font(.title2)
                        .foregroundStyle(.purple)
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    onDecline()
                } label: {
                    Text("Decline")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    onApprove()
                } label: {
                    Text("Approve")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func verificationColor(for status: VerificationStatus) -> Color {
        switch status {
        case .vip: return .yellow
        case .creator: return .purple
        case .influencer: return .blue
        case .artist: return .pink
        case .none: return .gray
        }
    }
}

// MARK: - Hosted Party Row

struct HostedPartyRowView: View {
    let party: Party

    var body: some View {
        HStack(spacing: 12) {
            // Vibe
            Text(party.vibe.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.purple.opacity(0.2))
                .clipShape(Circle())

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(party.name)
                        .fontWeight(.medium)

                    if party.isActive {
                        if party.isHappeningNow {
                            Text("LIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.red)
                                .clipShape(Capsule())
                        } else {
                            Text("Active")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("Ended")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(party.formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Attendee count
            VStack(alignment: .trailing) {
                HStack(spacing: 2) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                    Text("\(party.currentAttendeeCount)")
                        .font(.subheadline)
                }
                .foregroundStyle(.purple)

                if let max = party.maxAttendees {
                    Text("/ \(max)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let viewModel = PartiesViewModel()

    return HostDashboardView()
        .environmentObject(viewModel)
}
