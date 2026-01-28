import Foundation
import SwiftData
import Combine

@MainActor
final class SetTimesViewModel: ObservableObject {

    // MARK: - Published State
    @Published var events: [Event] = []
    @Published var selectedEvent: Event?
    @Published var allStages: [Stage] = []  // All stages for current event
    @Published var setTimes: [SetTime] = []
    @Published var favoriteSetTimes: [SetTime] = []
    @Published var conflicts: [(SetTime, SetTime)] = []

    @Published var selectedDate: Date = Date()
    @Published var selectedStage: Stage?
    @Published var searchText = ""
    @Published var showFavoritesOnly = false

    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Dependencies
    private let notificationManager: NotificationManager
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadEvents()
        loadSetTimes()
    }

    // MARK: - Data Loading

    func loadEvents() {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.startDate)]
        )

        do {
            events = try modelContext.fetch(descriptor)
            if selectedEvent == nil, let first = events.first {
                selectedEvent = first
            }
            // Also load all stages for the selected event
            loadStages()
        } catch {
            errorMessage = "Failed to load events: \(error.localizedDescription)"
        }
    }

    func loadStages() {
        guard let modelContext = modelContext else { return }

        // Fetch stages - either from selected event or all stages
        let descriptor = FetchDescriptor<Stage>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            let stages = try modelContext.fetch(descriptor)
            // Filter to selected event if we have one
            if let event = selectedEvent {
                allStages = stages.filter { $0.event?.id == event.id }
            } else {
                allStages = stages
            }
        } catch {
            errorMessage = "Failed to load stages: \(error.localizedDescription)"
        }
    }

    func loadSetTimes() {
        guard let modelContext = modelContext else { return }

        var _: [Predicate<SetTime>] = []

        // Filter by event if selected
        // Note: Would need to filter through Stage -> Event relationship

        let descriptor = FetchDescriptor<SetTime>(
            sortBy: [SortDescriptor(\.startTime)]
        )

        do {
            let allSetTimes = try modelContext.fetch(descriptor)
            setTimes = filterSetTimes(allSetTimes)
            updateFavorites()
            checkConflicts()
        } catch {
            errorMessage = "Failed to load set times: \(error.localizedDescription)"
        }
    }

    private func filterSetTimes(_ times: [SetTime]) -> [SetTime] {
        var filtered = times

        // Filter by date
        let calendar = Calendar.current
        filtered = filtered.filter { setTime in
            calendar.isDate(setTime.startTime, inSameDayAs: selectedDate)
        }

        // Filter by stage
        if let stage = selectedStage {
            filtered = filtered.filter { $0.stage?.id == stage.id }
        }

        // Filter by search
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.artistName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter favorites only
        if showFavoritesOnly {
            filtered = filtered.filter { $0.isFavorite }
        }

        return filtered.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Favorites

    func toggleFavorite(_ setTime: SetTime) {
        setTime.isFavorite.toggle()
        try? modelContext?.save()

        updateFavorites()
        checkConflicts()

        // Schedule or cancel notification
        if setTime.isFavorite {
            scheduleNotification(for: setTime)
        } else {
            notificationManager.cancelSetTimeNotification(for: setTime)
        }
    }

    private func updateFavorites() {
        favoriteSetTimes = setTimes.filter { $0.isFavorite }
    }

    private func checkConflicts() {
        conflicts = favoriteSetTimes.favoriteConflicts
    }

    // MARK: - Notifications

    private func scheduleNotification(for setTime: SetTime) {
        guard let stageName = setTime.stage?.name else { return }

        // Default to 10 minutes if not set
        var leadMinutes = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.notifyBefore)
        if leadMinutes == 0 {
            leadMinutes = 10 // Default 10 minutes
        }
        let leadTime = TimeInterval(leadMinutes * 60)

        Task {
            await notificationManager.scheduleSetTimeNotification(
                for: setTime,
                stageName: stageName,
                leadTime: leadTime
            )
        }
    }

    func scheduleAllFavoriteNotifications() async {
        for setTime in favoriteSetTimes {
            if let stageName = setTime.stage?.name {
                await notificationManager.scheduleSetTimeNotification(
                    for: setTime,
                    stageName: stageName
                )
            }
        }
    }

    // MARK: - Import from JSON

    func importFromBundle() async {
        guard let url = Bundle.main.url(forResource: "sample_festivals", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[SetTimes] No sample data found")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let container = try decoder.decode(EventContainer.self, from: data)

            for eventData in container.events {
                let event = Event(
                    id: eventData.id,
                    name: eventData.name,
                    venue: eventData.venue,
                    city: eventData.city,
                    startDate: eventData.startDate,
                    endDate: eventData.endDate,
                    imageUrl: eventData.imageUrl,
                    websiteUrl: eventData.websiteUrl
                )

                modelContext?.insert(event)

                for stageData in eventData.stages {
                    let stage = Stage(
                        id: UUID(uuidString: stageData.id) ?? UUID(),
                        name: stageData.name,
                        color: stageData.color
                    )
                    stage.event = event
                    modelContext?.insert(stage)

                    for setTimeData in eventData.setTimes.filter({ $0.stageId == stageData.id }) {
                        let setTime = SetTime(
                            artistName: setTimeData.artistName,
                            startTime: setTimeData.startTime,
                            endTime: setTimeData.endTime
                        )
                        setTime.stage = stage
                        modelContext?.insert(setTime)
                    }
                }
            }

            try modelContext?.save()
            loadEvents()
            loadSetTimes()

        } catch {
            errorMessage = "Failed to import data: \(error.localizedDescription)"
        }
    }
}

// MARK: - JSON Decoding Types

private struct EventContainer: Codable {
    let events: [EventData]
}

private struct EventData: Codable {
    let id: String
    let name: String
    let venue: String
    let city: String
    let startDate: Date
    let endDate: Date
    let imageUrl: String?
    let websiteUrl: String?
    let stages: [StageData]
    let setTimes: [SetTimeData]
}

private struct StageData: Codable {
    let id: String
    let name: String
    let color: String
}

private struct SetTimeData: Codable {
    let artistName: String
    let stageId: String
    let startTime: Date
    let endTime: Date
}
