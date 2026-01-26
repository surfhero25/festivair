import Foundation
import CoreLocation
import Combine

/// Manages offline venue data downloads and caching
@MainActor
final class OfflineMapService: ObservableObject {

    // MARK: - Singleton
    static let shared = OfflineMapService()

    // MARK: - Published State
    @Published private(set) var availableVenues: [FestivalVenue] = []
    @Published private(set) var downloadedVenues: [FestivalVenue] = []
    @Published private(set) var currentVenue: FestivalVenue?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // Facility data
    @Published private(set) var facilities: [Facility] = []
    @Published private(set) var stages: [VenueStage] = []

    // MARK: - Private
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var downloadTasks: [UUID: URLSessionDownloadTask] = [:]

    // MARK: - Configuration
    private let maxCacheSize: Int64 = 100_000_000 // 100 MB
    private let baseAPIURL = "https://api.festivair.app/v1" // Placeholder

    // MARK: - Init
    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("FestivAirVenues", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Load cached data
        loadCachedVenues()
    }

    // MARK: - Public API

    /// Fetch available venues from server (or use cached list)
    func fetchAvailableVenues() async {
        isLoading = true
        error = nil

        // In production, this would fetch from API
        // For now, load sample data
        availableVenues = loadSampleVenues()

        // Update download status for each venue
        for i in availableVenues.indices {
            let venueDataPath = cacheDirectory.appendingPathComponent("\(availableVenues[i].id).json")
            if fileManager.fileExists(atPath: venueDataPath.path) {
                availableVenues[i].downloadStatus = .downloaded
                if let attrs = try? fileManager.attributesOfItem(atPath: venueDataPath.path),
                   let size = attrs[.size] as? Int64 {
                    availableVenues[i].localDataSize = size
                }
            }
        }

        downloadedVenues = availableVenues.filter { $0.downloadStatus == .downloaded }

        isLoading = false
    }

    /// Download venue data for offline use
    func downloadVenue(_ venue: FestivalVenue) async throws {
        guard availableVenues.first(where: { $0.id == venue.id }) != nil else {
            throw OfflineMapError.venueNotFound
        }

        // Check if already downloading
        if let index = availableVenues.firstIndex(where: { $0.id == venue.id }),
           availableVenues[index].downloadStatus == .downloading {
            return // Already downloading
        }

        // Update status
        if let index = availableVenues.firstIndex(where: { $0.id == venue.id }) {
            availableVenues[index].downloadStatus = .downloading
            availableVenues[index].downloadProgress = 0
        }

        do {
            // In production, download from API
            // For now, generate sample data
            let bundle = generateSampleBundle(for: venue)

            // Save to cache
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(bundle)

            // Check cache size limit before writing
            let newSize = totalCacheSize + Int64(data.count)
            if newSize > maxCacheSize {
                if let index = availableVenues.firstIndex(where: { $0.id == venue.id }) {
                    availableVenues[index].downloadStatus = .failed
                }
                throw OfflineMapError.cacheFull
            }

            // Use atomic write - write to temp file first, then move
            let tempPath = cacheDirectory.appendingPathComponent("\(venue.id).tmp")
            let venueDataPath = cacheDirectory.appendingPathComponent("\(venue.id).json")

            try data.write(to: tempPath, options: .atomic)

            // Move temp to final location
            if fileManager.fileExists(atPath: venueDataPath.path) {
                try fileManager.removeItem(at: venueDataPath)
            }
            try fileManager.moveItem(at: tempPath, to: venueDataPath)

            // Update status
            if let index = availableVenues.firstIndex(where: { $0.id == venue.id }) {
                availableVenues[index].downloadStatus = .downloaded
                availableVenues[index].downloadProgress = 1.0
                availableVenues[index].downloadedAt = Date()
                availableVenues[index].localDataSize = Int64(data.count)
            }

            downloadedVenues = availableVenues.filter { $0.downloadStatus == .downloaded }

        } catch {
            // Clean up temp file if it exists
            let tempPath = cacheDirectory.appendingPathComponent("\(venue.id).tmp")
            try? fileManager.removeItem(at: tempPath)

            if let index = availableVenues.firstIndex(where: { $0.id == venue.id }) {
                availableVenues[index].downloadStatus = .failed
            }
            throw error
        }
    }

    /// Delete downloaded venue data
    /// - Parameter force: If true, will delete even if venue is currently loaded
    /// - Throws: OfflineMapError.venueInUse if venue is currently loaded and force is false
    func deleteVenue(_ venue: FestivalVenue, force: Bool = false) throws {
        // Check if venue is currently in use
        if currentVenue?.id == venue.id && !force {
            throw OfflineMapError.venueInUse
        }

        let venueDataPath = cacheDirectory.appendingPathComponent("\(venue.id).json")

        if fileManager.fileExists(atPath: venueDataPath.path) {
            try fileManager.removeItem(at: venueDataPath)
        }

        if let index = availableVenues.firstIndex(where: { $0.id == venue.id }) {
            availableVenues[index].downloadStatus = .notDownloaded
            availableVenues[index].localDataSize = 0
            availableVenues[index].downloadedAt = nil
        }

        downloadedVenues = availableVenues.filter { $0.downloadStatus == .downloaded }

        // Clear current venue if it was deleted (only reachable with force=true)
        if currentVenue?.id == venue.id {
            currentVenue = nil
            facilities = []
            stages = []
        }
    }

    /// Load venue data for use
    func loadVenueData(_ venue: FestivalVenue) throws {
        let venueDataPath = cacheDirectory.appendingPathComponent("\(venue.id).json")

        guard fileManager.fileExists(atPath: venueDataPath.path) else {
            throw OfflineMapError.venueNotDownloaded
        }

        let data = try Data(contentsOf: venueDataPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(VenueDataBundle.self, from: data)

        currentVenue = bundle.venue
        facilities = bundle.facilities
        stages = bundle.stages
    }

    /// Auto-detect venue based on user location
    func detectVenue(at location: CLLocationCoordinate2D) -> FestivalVenue? {
        // First check downloaded venues
        if let venue = downloadedVenues.first(where: { $0.contains(location) }) {
            return venue
        }
        // Then check all available
        return availableVenues.first(where: { $0.contains(location) })
    }

    /// Get facilities of a specific type
    func facilities(ofType type: FacilityType) -> [Facility] {
        facilities.filter { $0.type == type }
    }

    /// Get nearest facility of a type
    func nearestFacility(ofType type: FacilityType, from location: CLLocationCoordinate2D) -> (facility: Facility, distance: Double)? {
        let matching = facilities(ofType: type)
        let userLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)

        var nearest: (Facility, Double)?

        for facility in matching {
            let facilityLocation = CLLocation(latitude: facility.latitude, longitude: facility.longitude)
            let distance = userLocation.distance(from: facilityLocation)

            if nearest == nil || distance < nearest!.1 {
                nearest = (facility, distance)
            }
        }

        return nearest
    }

    /// Facilities for current venue (or sample data if none loaded)
    var facilitiesForCurrentVenue: [Facility] {
        // If we have loaded venue data, return those facilities
        if !facilities.isEmpty {
            return facilities
        }
        // Otherwise return empty array - user needs to download venue data
        return []
    }

    /// Get total cache size
    var totalCacheSize: Int64 {
        downloadedVenues.reduce(0) { $0 + $1.localDataSize }
    }

    var formattedCacheSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalCacheSize)
    }

    // MARK: - Private Helpers

    private func loadCachedVenues() {
        // Load list of downloaded venues from UserDefaults or scan cache directory
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return
        }

        var corruptFiles: [URL] = []

        for fileURL in contents where fileURL.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let bundle = try decoder.decode(VenueDataBundle.self, from: data)

                var venue = bundle.venue
                venue.downloadStatus = .downloaded
                if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? Int64 {
                    venue.localDataSize = size
                }
                downloadedVenues.append(venue)
            } catch {
                print("[OfflineMap] Failed to load cached venue: \(error) - marking for deletion")
                corruptFiles.append(fileURL)
            }
        }

        // Clean up corrupt files
        for fileURL in corruptFiles {
            do {
                try fileManager.removeItem(at: fileURL)
                print("[OfflineMap] Deleted corrupt cache file: \(fileURL.lastPathComponent)")
            } catch {
                print("[OfflineMap] Failed to delete corrupt file: \(error)")
            }
        }

        // Also clean up any orphaned temp files
        if let allFiles = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for fileURL in allFiles where fileURL.pathExtension == "tmp" {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Sample Data (for development/demo)

    private func loadSampleVenues() -> [FestivalVenue] {
        [
            // Test venue - Mira Mesa area (for local testing)
            FestivalVenue(
                name: "Test Festival - Mira Mesa",
                description: "Local test venue for development",
                minLatitude: 32.900,
                maxLatitude: 32.930,
                minLongitude: -117.155,
                maxLongitude: -117.120,
                eventId: nil,
                imageUrl: nil
            ),
            FestivalVenue(
                name: "Electric Daisy Carnival",
                description: "Las Vegas Motor Speedway",
                minLatitude: 36.268,
                maxLatitude: 36.275,
                minLongitude: -115.015,
                maxLongitude: -115.000,
                eventId: nil,
                imageUrl: nil
            ),
            FestivalVenue(
                name: "Coachella Valley",
                description: "Empire Polo Club, Indio",
                minLatitude: 33.678,
                maxLatitude: 33.688,
                minLongitude: -116.242,
                maxLongitude: -116.230,
                eventId: nil,
                imageUrl: nil
            ),
            FestivalVenue(
                name: "Bonnaroo Farm",
                description: "Great Stage Park, Manchester TN",
                minLatitude: 35.475,
                maxLatitude: 35.490,
                minLongitude: -86.065,
                maxLongitude: -86.045,
                eventId: nil,
                imageUrl: nil
            ),
            FestivalVenue(
                name: "Lollapalooza Chicago",
                description: "Grant Park, Chicago",
                minLatitude: 41.870,
                maxLatitude: 41.880,
                minLongitude: -87.625,
                maxLongitude: -87.615,
                eventId: nil,
                imageUrl: nil
            )
        ]
    }

    private func generateSampleBundle(for venue: FestivalVenue) -> VenueDataBundle {
        // Generate sample facilities scattered around the venue
        let facilityTypes: [FacilityType] = [
            .water, .water, .water, .water,
            .bathroom, .bathroom, .bathroom, .bathroom, .bathroom,
            .medical, .medical,
            .food, .food, .food, .food, .food,
            .bar, .bar, .bar,
            .merchandise, .merchandise,
            .charging, .charging,
            .atm, .atm,
            .entrance, .entrance,
            .exit, .exit,
            .info
        ]

        var facilities: [Facility] = []
        for (index, type) in facilityTypes.enumerated() {
            let lat = venue.minLatitude + Double.random(in: 0...(venue.maxLatitude - venue.minLatitude))
            let lon = venue.minLongitude + Double.random(in: 0...(venue.maxLongitude - venue.minLongitude))

            facilities.append(Facility(
                name: "\(type.displayName) \(index + 1)",
                type: type,
                latitude: lat,
                longitude: lon,
                venueId: venue.id
            ))
        }

        // Generate sample stages
        let stageNames = ["Main Stage", "Cosmic Meadow", "Circuit Grounds", "Neon Garden", "Bass Pod"]
        var stages: [VenueStage] = []
        for name in stageNames {
            let lat = venue.minLatitude + Double.random(in: 0.2...0.8) * (venue.maxLatitude - venue.minLatitude)
            let lon = venue.minLongitude + Double.random(in: 0.2...0.8) * (venue.maxLongitude - venue.minLongitude)

            stages.append(VenueStage(
                id: UUID(),
                name: name,
                latitude: lat,
                longitude: lon,
                capacity: Int.random(in: 5000...50000),
                description: nil
            ))
        }

        return VenueDataBundle(
            venue: venue,
            facilities: facilities,
            stages: stages,
            version: 1,
            generatedAt: Date()
        )
    }
}

// MARK: - Errors
enum OfflineMapError: LocalizedError {
    case venueNotFound
    case venueNotDownloaded
    case downloadFailed
    case cacheFull
    case venueInUse

    var errorDescription: String? {
        switch self {
        case .venueNotFound: return "Venue not found"
        case .venueNotDownloaded: return "Venue data not downloaded"
        case .downloadFailed: return "Download failed"
        case .cacheFull: return "Cache storage is full"
        case .venueInUse: return "Cannot delete venue that is currently loaded"
        }
    }
}
