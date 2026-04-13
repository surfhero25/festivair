import Foundation

/// Communicates with the FestivAir backend API for events and vendor data.
actor FestivAirAPIService {

    static let shared = FestivAirAPIService()

    // MARK: - Configuration

    private let baseURL = "http://187.124.249.219:8080"
    private let apiKey: String = {
        guard let key = Bundle.main.infoDictionary?["FESTIVAIR_API_KEY"] as? String, !key.isEmpty else {
            fatalError("FESTIVAIR_API_KEY not set in Info.plist")
        }
        return key
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Event Models

    struct APIEvent: Codable, Identifiable {
        let id: String
        let name: String
        let venue: String?
        let city: String?
        let state: String?
        let country: String
        let latitude: Double?
        let longitude: Double?
        let start_date: Date
        let end_date: Date
        let website: String?
        let image_url: String?
        let description: String?
        let is_verified: Bool
        let estimated_attendance: Int?
        let genres: String?
    }

    struct APIVendorLocation: Codable, Identifiable {
        let id: String
        let vendor_id: String
        let event_id: String
        let latitude: Double
        let longitude: Double
        let booth_name: String?
        let description: String?
        let is_active: Bool
        let hours: String?
        let business_name: String?
    }

    // MARK: - Events

    /// Fetch upcoming events
    func fetchUpcomingEvents(limit: Int = 50) async throws -> [APIEvent] {
        let url = URL(string: "\(baseURL)/events/?upcoming=true&limit=\(limit)")!
        return try await request(url: url)
    }

    /// Fetch a specific event
    func fetchEvent(id: String) async throws -> APIEvent {
        let url = URL(string: "\(baseURL)/events/\(id)")!
        return try await request(url: url)
    }

    // MARK: - Vendor Locations

    /// Fetch vendor locations for a specific event (for map pins)
    func fetchVendorLocations(eventId: String) async throws -> [APIVendorLocation] {
        let url = URL(string: "\(baseURL)/vendors/locations/\(eventId)")!
        return try await request(url: url)
    }

    // MARK: - Private

    private func request<T: Decodable>(url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        return try decoder.decode(T.self, from: data)
    }

    enum APIError: Error, LocalizedError {
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .requestFailed: return "API request failed"
            }
        }
    }
}
