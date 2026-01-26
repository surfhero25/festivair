import SwiftUI

/// Settings view for managing offline venue data downloads
struct OfflineMapsView: View {
    @StateObject private var offlineMapService = OfflineMapService.shared
    @State private var showDeleteConfirmation = false
    @State private var venueToDelete: FestivalVenue?

    var body: some View {
        List {
            // Cache info section
            Section {
                HStack {
                    Label("Cache Size", systemImage: "externaldrive.fill")
                    Spacer()
                    Text(offlineMapService.formattedCacheSize)
                        .foregroundStyle(.secondary)
                }

                if !offlineMapService.downloadedVenues.isEmpty {
                    Button(role: .destructive) {
                        // Clear all cache
                        for venue in offlineMapService.downloadedVenues {
                            try? offlineMapService.deleteVenue(venue)
                        }
                    } label: {
                        Label("Clear All Cache", systemImage: "trash")
                    }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Downloaded maps allow facility locations to work offline without internet.")
            }

            // Downloaded venues section
            if !offlineMapService.downloadedVenues.isEmpty {
                Section {
                    ForEach(offlineMapService.downloadedVenues) { venue in
                        DownloadedVenueRow(venue: venue) {
                            venueToDelete = venue
                            showDeleteConfirmation = true
                        }
                    }
                } header: {
                    Text("Downloaded")
                }
            }

            // Available venues section
            Section {
                if offlineMapService.isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading venues...")
                            .foregroundStyle(.secondary)
                    }
                } else if offlineMapService.availableVenues.isEmpty {
                    Text("No venues available")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(offlineMapService.availableVenues.filter { $0.downloadStatus != .downloaded }) { venue in
                        AvailableVenueRow(venue: venue) {
                            Task {
                                try? await offlineMapService.downloadVenue(venue)
                            }
                        }
                    }
                }
            } header: {
                Text("Available Venues")
            } footer: {
                Text("Download venue data before the festival for best offline experience.")
            }
        }
        .navigationTitle("Offline Maps")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await offlineMapService.fetchAvailableVenues()
        }
        .task {
            await offlineMapService.fetchAvailableVenues()
        }
        .alert("Delete Venue Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let venue = venueToDelete {
                    try? offlineMapService.deleteVenue(venue)
                }
            }
        } message: {
            if let venue = venueToDelete {
                Text("This will delete the offline data for \(venue.name). You can re-download it anytime.")
            }
        }
    }
}

// MARK: - Downloaded Venue Row
private struct DownloadedVenueRow: View {
    let venue: FestivalVenue
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(venue.sizeDescription)
                    Text("•")
                    Text(formattedSize(venue.localDataSize))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Available Venue Row
private struct AvailableVenueRow: View {
    let venue: FestivalVenue
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                if venue.downloadStatus == .downloading {
                    ProgressView()
                } else {
                    Image(systemName: venue.downloadStatus.icon)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                }
            }
            .frame(width: 30)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name)
                    .fontWeight(.medium)

                if let description = venue.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(venue.sizeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Download button
            if venue.downloadStatus != .downloading {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconColor: Color {
        switch venue.downloadStatus {
        case .notDownloaded: return .secondary
        case .downloading: return .blue
        case .downloaded: return .green
        case .updateAvailable: return .orange
        case .failed: return .red
        }
    }
}

#Preview {
    NavigationStack {
        OfflineMapsView()
    }
}
