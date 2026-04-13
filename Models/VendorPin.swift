import Foundation
import CoreLocation

/// Represents a vendor location pin on the festival map.
struct VendorPin: Identifiable {
    let id: String
    let businessName: String
    let boothName: String?
    let category: String?
    let description: String?
    let hours: String?
    let coordinate: CLLocationCoordinate2D

    /// SF Symbol for the vendor category
    var categoryIcon: String {
        switch category?.lowercased() {
        case "food": return "fork.knife"
        case "beverage": return "cup.and.saucer.fill"
        case "merch": return "tshirt.fill"
        case "sponsor": return "star.fill"
        case "services": return "wrench.and.screwdriver.fill"
        default: return "mappin.circle.fill"
        }
    }

    /// Pin color based on category
    var pinColorName: String {
        switch category?.lowercased() {
        case "food": return "orange"
        case "beverage": return "blue"
        case "merch": return "purple"
        case "sponsor": return "yellow"
        default: return "gray"
        }
    }

    /// Create from API response
    static func from(_ apiLocation: FestivAirAPIService.APIVendorLocation) -> VendorPin {
        VendorPin(
            id: apiLocation.id,
            businessName: apiLocation.business_name ?? "Vendor",
            boothName: apiLocation.booth_name,
            category: nil,
            description: apiLocation.description,
            hours: apiLocation.hours,
            coordinate: CLLocationCoordinate2D(
                latitude: apiLocation.latitude,
                longitude: apiLocation.longitude
            )
        )
    }
}
