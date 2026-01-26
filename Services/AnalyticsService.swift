import Foundation
import CoreLocation
import CoreMotion

/// Service for tracking user festival analytics (Premium feature)
@MainActor
final class AnalyticsService: ObservableObject {

    // MARK: - Singleton
    static let shared = AnalyticsService()

    // MARK: - Published State
    @Published private(set) var stepsToday: Int = 0
    @Published private(set) var distanceKm: Double = 0
    @Published private(set) var stagesVisited: Set<String> = []
    @Published private(set) var activeMinutes: Int = 0
    @Published private(set) var peakHour: Int?  // Hour of most activity (0-23)

    // Historical data
    @Published private(set) var dailyStats: [DailyStats] = []

    // MARK: - Private
    private let pedometer = CMPedometer()
    private var lastLocation: CLLocation?
    private var locationHistory: [CLLocation] = []
    private var stageVisitTimes: [String: Date] = [:]  // Stage ID -> first visit time
    private let stageProximityMeters: Double = 50

    // Tracking state
    private var isTracking = false
    private var trackingStartTime: Date?

    // MARK: - Init
    private init() {
        loadStoredData()
    }

    // MARK: - Start/Stop Tracking

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        trackingStartTime = Date()

        // Start pedometer
        if CMPedometer.isStepCountingAvailable() {
            let startOfDay = Calendar.current.startOfDay(for: Date())
            pedometer.startUpdates(from: startOfDay) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                Task { @MainActor in
                    self?.stepsToday = data.numberOfSteps.intValue
                    if let distance = data.distance {
                        self?.distanceKm = distance.doubleValue / 1000
                    }
                }
            }
        }
    }

    func stopTracking() {
        isTracking = false
        pedometer.stopUpdates()
        saveData()
    }

    // MARK: - Location Updates

    func recordLocation(_ location: CLLocation) {
        guard isTracking else { return }

        // Track distance
        if let last = lastLocation {
            let distance = location.distance(from: last)
            // Only count if reasonable (not a GPS jump)
            if distance < 100 {
                distanceKm += distance / 1000
            }
        }

        lastLocation = location
        locationHistory.append(location)

        // Keep only last hour of location history
        let oneHourAgo = Date().addingTimeInterval(-3600)
        locationHistory = locationHistory.filter { $0.timestamp > oneHourAgo }

        // Calculate active minutes (if moving significantly)
        updateActiveMinutes()
    }

    // MARK: - Stage Visits

    func recordStageVisit(_ stageId: String, stageName: String) {
        guard isTracking else { return }

        if !stagesVisited.contains(stageId) {
            stagesVisited.insert(stageId)
            stageVisitTimes[stageId] = Date()
        }
    }

    func checkStageProximity(userLocation: CLLocation, stages: [(id: String, name: String, latitude: Double, longitude: Double)]) {
        for stage in stages {
            let stageLocation = CLLocation(latitude: stage.latitude, longitude: stage.longitude)
            let distance = userLocation.distance(from: stageLocation)

            if distance <= stageProximityMeters {
                recordStageVisit(stage.id, stageName: stage.name)
            }
        }
    }

    // MARK: - Active Minutes

    private func updateActiveMinutes() {
        // Simple heuristic: count as active if we have location updates
        // More sophisticated: check speed/movement patterns
        if let startTime = trackingStartTime {
            let totalMinutes = Int(Date().timeIntervalSince(startTime) / 60)
            // Estimate active minutes as a fraction of total
            activeMinutes = min(totalMinutes, stepsToday / 100)  // Rough estimate
        }
    }

    // MARK: - Peak Hour Calculation

    func calculatePeakHour() {
        var hourCounts: [Int: Int] = [:]

        for location in locationHistory {
            let hour = Calendar.current.component(.hour, from: location.timestamp)
            hourCounts[hour, default: 0] += 1
        }

        peakHour = hourCounts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Festival Summary

    func generateFestivalSummary() -> FestivalSummary {
        calculatePeakHour()

        return FestivalSummary(
            totalSteps: stepsToday,
            totalDistanceKm: distanceKm,
            stagesVisited: stagesVisited.count,
            activeMinutes: activeMinutes,
            peakHour: peakHour,
            topStage: findTopStage(),
            daysAttended: dailyStats.count + 1  // Include today
        )
    }

    private func findTopStage() -> String? {
        // For now, return the first visited stage
        // In production, track time spent at each stage
        return stageVisitTimes.keys.first
    }

    // MARK: - Daily Stats

    func saveDailyStats() {
        let today = DailyStats(
            date: Date(),
            steps: stepsToday,
            distanceKm: distanceKm,
            stagesVisited: stagesVisited.count,
            activeMinutes: activeMinutes
        )

        // Check if we already have stats for today
        let calendar = Calendar.current
        if let index = dailyStats.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today.date) }) {
            dailyStats[index] = today
        } else {
            dailyStats.append(today)
        }

        saveData()
    }

    // MARK: - Reset

    func resetDailyStats() {
        stepsToday = 0
        distanceKm = 0
        stagesVisited = []
        activeMinutes = 0
        peakHour = nil
        locationHistory = []
        stageVisitTimes = [:]
        trackingStartTime = Date()
    }

    // MARK: - Persistence

    private func loadStoredData() {
        if let data = UserDefaults.standard.data(forKey: "FestivAir.DailyStats"),
           let stats = try? JSONDecoder().decode([DailyStats].self, from: data) {
            dailyStats = stats
        }

        if let data = UserDefaults.standard.data(forKey: "FestivAir.VisitedStages"),
           let stages = try? JSONDecoder().decode(Set<String>.self, from: data) {
            stagesVisited = stages
        }

        stepsToday = UserDefaults.standard.integer(forKey: "FestivAir.StepsToday")
        distanceKm = UserDefaults.standard.double(forKey: "FestivAir.DistanceKm")
        activeMinutes = UserDefaults.standard.integer(forKey: "FestivAir.ActiveMinutes")
    }

    private func saveData() {
        if let data = try? JSONEncoder().encode(dailyStats) {
            UserDefaults.standard.set(data, forKey: "FestivAir.DailyStats")
        }

        if let data = try? JSONEncoder().encode(stagesVisited) {
            UserDefaults.standard.set(data, forKey: "FestivAir.VisitedStages")
        }

        UserDefaults.standard.set(stepsToday, forKey: "FestivAir.StepsToday")
        UserDefaults.standard.set(distanceKm, forKey: "FestivAir.DistanceKm")
        UserDefaults.standard.set(activeMinutes, forKey: "FestivAir.ActiveMinutes")
    }
}

// MARK: - Supporting Types

struct DailyStats: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let steps: Int
    let distanceKm: Double
    let stagesVisited: Int
    let activeMinutes: Int
}

struct FestivalSummary {
    let totalSteps: Int
    let totalDistanceKm: Double
    let stagesVisited: Int
    let activeMinutes: Int
    let peakHour: Int?
    let topStage: String?
    let daysAttended: Int

    var formattedDistance: String {
        String(format: "%.1f km", totalDistanceKm)
    }

    var formattedPeakHour: String? {
        guard let hour = peakHour,
              let date = Calendar.current.date(from: DateComponents(hour: hour)) else { return nil }
        return Formatters.formatter(for: "h a").string(from: date)
    }

    var activityLevel: String {
        if totalSteps > 20000 { return "Festival Warrior" }
        if totalSteps > 15000 { return "Stage Hopper" }
        if totalSteps > 10000 { return "Active Explorer" }
        if totalSteps > 5000 { return "Casual Viber" }
        return "Chill Mode"
    }
}
