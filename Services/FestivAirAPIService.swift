import Foundation

/// Communicates with the FestivAir backend API for events and vendor data.
actor FestivAirAPIService {

    static let shared = FestivAirAPIService()

    // MARK: - Configuration

    private let baseURL: URL = {
        let configuredURL = Bundle.main.infoDictionary?["FESTIVAIR_API_BASE_URL"] as? String
        let urlString = Self.configValue(configuredURL)
        return URL(string: urlString?.isEmpty == false ? urlString! : "https://api.festivair.app")
            ?? URL(string: "https://api.festivair.app")!
    }()

    private let apiKey: String? = {
        let key = Bundle.main.infoDictionary?["FESTIVAIR_API_KEY"] as? String
        return Self.configValue(key)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func configValue(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed,
              !trimmed.isEmpty,
              !(trimmed.hasPrefix("$(") && trimmed.hasSuffix(")")) else {
            return nil
        }
        return trimmed
    }

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
        var components = URLComponents(url: baseURL.appendingPathComponent("events/"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "upcoming", value: "true"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { throw APIError.invalidURL }
        return try await request(url: url)
    }

    /// Fetch a specific event
    func fetchEvent(id: String) async throws -> APIEvent {
        let url = baseURL
            .appendingPathComponent("events")
            .appendingPathComponent(id)
        return try await request(url: url)
    }

    // MARK: - Vendor Locations

    /// Fetch vendor locations for a specific event (for map pins)
    func fetchVendorLocations(eventId: String) async throws -> [APIVendorLocation] {
        let url = baseURL
            .appendingPathComponent("vendors")
            .appendingPathComponent("locations")
            .appendingPathComponent(eventId)
        return try await request(url: url)
    }

    // MARK: - Private

    private func request<T: Decodable>(url: URL) async throws -> T {
        var req = URLRequest(url: url)
        if let apiKey {
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        req.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        return try decoder.decode(T.self, from: data)
    }

    enum APIError: Error, LocalizedError {
        case invalidURL
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL"
            case .requestFailed: return "API request failed"
            }
        }
    }
}
