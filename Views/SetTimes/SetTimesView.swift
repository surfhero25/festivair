import SwiftUI

struct SetTimesView: View {
    @EnvironmentObject var appState: AppState

    private var viewModel: SetTimesViewModel {
        appState.setTimesViewModel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date picker
                DatePickerBar(
                    selectedDate: Binding(
                        get: { viewModel.selectedDate },
                        set: { newValue in
                            viewModel.selectedDate = newValue
                            viewModel.loadSetTimes()
                        }
                    ),
                    events: viewModel.events
                )

                // Stage filter
                StageFilterBar(
                    stages: viewModel.allStages,
                    selectedStage: Binding(
                        get: { viewModel.selectedStage },
                        set: { newValue in
                            viewModel.selectedStage = newValue
                            viewModel.loadSetTimes()
                        }
                    )
                )

                // Conflict warning
                if !viewModel.conflicts.isEmpty {
                    ConflictBanner(conflicts: viewModel.conflicts)
                }

                // Set times list
                if viewModel.isLoading {
                    ProgressView("Loading set times...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.setTimes.isEmpty {
                    EmptySetTimesView(showFavoritesOnly: viewModel.showFavoritesOnly)
                } else {
                    List {
                        ForEach(viewModel.setTimes, id: \.id) { setTime in
                            SetTimeRow(setTime: setTime) {
                                Haptics.medium()
                                viewModel.toggleFavorite(setTime)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Set Times")
            .searchable(
                text: Binding(
                    get: { viewModel.searchText },
                    set: { newValue in
                        viewModel.searchText = newValue
                        viewModel.loadSetTimes()
                    }
                ),
                prompt: "Search artists"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.selection()
                        viewModel.showFavoritesOnly.toggle()
                        viewModel.loadSetTimes()
                    } label: {
                        Image(systemName: viewModel.showFavoritesOnly ? "heart.fill" : "heart")
                            .foregroundStyle(viewModel.showFavoritesOnly ? .red : .primary)
                    }
                }
            }
        }
    }
}

// MARK: - Empty State
struct EmptySetTimesView: View {
    let showFavoritesOnly: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: showFavoritesOnly ? "heart.slash" : "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(showFavoritesOnly ? "No favorites yet" : "No set times found")
                .font(.headline)
            Text(showFavoritesOnly ? "Tap the heart on a set to add it to favorites" : "Try adjusting your filters")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Conflict Banner
struct ConflictBanner: View {
    let conflicts: [(SetTime, SetTime)]

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(conflicts.count) schedule conflict\(conflicts.count > 1 ? "s" : "")")
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}

// MARK: - Date Picker Bar
struct DatePickerBar: View {
    @Binding var selectedDate: Date
    let events: [Event]

    private var eventDates: [Date] {
        guard let event = events.first else {
            // Fallback to next 3 days if no events
            let calendar = Calendar.current
            let today = Date()
            return (0..<3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        }

        var dates: [Date] = []
        let calendar = Calendar.current
        var current = calendar.startOfDay(for: event.startDate)
        let end = calendar.startOfDay(for: event.endDate)

        // Safety limit to prevent infinite loop (max 30 day festival)
        var iterations = 0
        let maxIterations = 30

        while current <= end && iterations < maxIterations {
            dates.append(current)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
            iterations += 1
        }
        return dates
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(eventDates, id: \.self) { date in
                    DateChip(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    ) {
                        selectedDate = date
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

struct DateChip: View {
    let date: Date
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(dayName)
                    .font(.caption)
                Text(dayNumber)
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? .purple : .clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var dayName: String {
        Formatters.dayShort.string(from: date)
    }

    private var dayNumber: String {
        Formatters.formatter(for: "d").string(from: date)
    }
}

// MARK: - Stage Filter Bar
struct StageFilterBar: View {
    let stages: [Stage]
    @Binding var selectedStage: Stage?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All Stages",
                    isSelected: selectedStage == nil
                ) {
                    selectedStage = nil
                }

                ForEach(stages, id: \.id) { stage in
                    FilterChip(
                        title: stage.name,
                        isSelected: selectedStage?.id == stage.id
                    ) {
                        selectedStage = stage
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? .purple.opacity(0.2) : .secondary.opacity(0.1))
                .foregroundStyle(isSelected ? .purple : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

// MARK: - Set Time Row
struct SetTimeRow: View {
    let setTime: SetTime
    let onFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Time column
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedStartTime)
                    .font(.headline.monospacedDigit())
                if let stageName = setTime.stage?.name {
                    Text(stageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, alignment: .leading)

            // Artist info
            VStack(alignment: .leading, spacing: 4) {
                Text(setTime.artistName)
                    .font(.headline)

                HStack(spacing: 4) {
                    if setTime.isLive {
                        Text("LIVE")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    } else if let minutes = setTime.minutesUntilStart, minutes <= 30 {
                        Text("In \(minutes) min")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Text("\(setTime.durationMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Favorite button
            Button(action: onFavorite) {
                Image(systemName: setTime.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(setTime.isFavorite ? .red : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(setTime.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(setTime.artistName), \(formattedStartTime), \(setTime.stage?.name ?? ""), \(setTime.durationMinutes) minutes")
        .accessibilityHint(setTime.isFavorite ? "Double tap to remove from favorites" : "Double tap to add to favorites")
    }

    private var formattedStartTime: String {
        Formatters.time.string(from: setTime.startTime)
    }
}

#Preview {
    SetTimesView()
        .environmentObject(AppState())
}
