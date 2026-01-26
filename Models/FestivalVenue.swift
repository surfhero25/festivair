import Foundation
import CoreLocation

/// Represents a festival venue with boundaries and downloadable offline data
struct FestivalVenue: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String?

    // Bounding box for the venue
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    // Center point for initial map focus
    let centerLatitude: Double
    let centerLongitude: Double

    // Metadata
    let eventId: UUID?
    let imageUrl: String?
    let lastUpdated: Date

    // Download status (not persisted to JSON)
    var downloadStatus: DownloadStatus = .notDownloaded
    var downloadProgress: Double = 0
    var downloadedAt: Date?
    var localDataSize: Int64 = 0

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    var boundingBox: (southwest: CLLocationCoordinate2D, northeast: CLLocationCoordinate2D) {
        (
            CLLocationCoordinate2D(latitude: minLatitude, longitude: minLongitude),
            CLLocationCoordinate2D(latitude: maxLatitude, longitude: maxLongitude)
        )
    }

    /// Check if a coordinate is within the venue bounds
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minLatitude &&
        coordinate.latitude <= maxLatitude &&
        coordinate.longitude >= minLongitude &&
        coordinate.longitude <= maxLongitude
    }

    /// Approximate area in square meters
    var approximateAreaMeters: Double {
        let latDistance = (maxLatitude - minLatitude) * 111_000 // ~111km per degree
        let lonDistance = (maxLongitude - minLongitude) * 111_000 * cos(centerLatitude * .pi / 180)
        return latDistance * lonDistance
    }

    /// Human-readable size
    var sizeDescription: String {
        let area = approximateAreaMeters
        if area < 10_000 {
            return "Small venue"
        } else if area < 100_000 {
            return "Medium venue"
        } else if area < 500_000 {
            return "Large venue"
        } else {
            return "Massive venue"
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        minLatitude: Double,
        maxLatitude: Double,
        minLongitude: Double,
        maxLongitude: Double,
        centerLatitude: Double? = nil,
        centerLongitude: Double? = nil,
        eventId: UUID? = nil,
        imageUrl: String? = nil,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
        self.centerLatitude = centerLatitude ?? (minLatitude + maxLatitude) / 2
        self.centerLongitude = centerLongitude ?? (minLongitude + maxLongitude) / 2
        self.eventId = eventId
        self.imageUrl = imageUrl
        self.lastUpdated = lastUpdated
    }

    // Coding keys - exclude runtime state
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case minLatitude, maxLatitude, minLongitude, maxLongitude
        case centerLatitude, centerLongitude
        case eventId, imageUrl, lastUpdated
    }
}

// MARK: - Download Status
enum DownloadStatus: String, Codable {
    case notDownloaded
    case downloading
    case downloaded
    case updateAvailable
    case failed

    var description: String {
        switch self {
        case .notDownloaded: return "Not downloaded"
        case .downloading: return "Downloading..."
        case .downloaded: return "Downloaded"
        case .updateAvailable: return "Update available"
        case .failed: return "Download failed"
        }
    }

    var icon: String {
        switch self {
        case .notDownloaded: return "arrow.down.circle"
        case .downloading: return "arrow.down.circle.dotted"
        case .downloaded: return "checkmark.circle.fill"
        case .updateAvailable: return "arrow.triangle.2.circlepath.circle"
        case .failed: return "exclamationmark.circle"
        }
    }
}

// MARK: - Venue Data Bundle
/// Contains all downloadable data for a venue
struct VenueDataBundle: Codable {
    let venue: FestivalVenue
    let facilities: [Facility]
    let stages: [VenueStage]
    let version: Int
    let generatedAt: Date

    /// Estimated size in bytes
    var estimatedSize: Int64 {
        // Rough estimate based on content
        let facilitiesSize = facilities.count * 200
        let stagesSize = stages.count * 300
        return Int64(1000 + facilitiesSize + stagesSize)
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: estimatedSize)
    }
}

// MARK: - Venue Stage
struct VenueStage: Identifiable, Codable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let capacity: Int?
    let description: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
