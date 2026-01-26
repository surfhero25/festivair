import SwiftUI
import CoreLocation

/// Quick widget showing nearest facilities of each type
struct NearestFacilityView: View {
    @ObservedObject var offlineMapService = OfflineMapService.shared
    let userLocation: CLLocationCoordinate2D?
    let onNavigate: (Facility) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find Nearest")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(FacilityType.quickAccess, id: \.self) { type in
                        NearestFacilityCard(
                            type: type,
                            nearest: nearestOfType(type),
                            onTap: { facility in
                                onNavigate(facility)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func nearestOfType(_ type: FacilityType) -> (facility: Facility, distance: Double)? {
        guard let location = userLocation else { return nil }
        return offlineMapService.nearestFacility(ofType: type, from: location)
    }
}

// MARK: - Nearest Facility Card
struct NearestFacilityCard: View {
    let type: FacilityType
    let nearest: (facility: Facility, distance: Double)?
    let onTap: (Facility) -> Void

    var body: some View {
        Button {
            if let facility = nearest?.facility {
                Haptics.light()
                onTap(facility)
            }
        } label: {
            VStack(spacing: 8) {
                // Icon
                ZStack {
                    Circle()
                        .fill(type.color.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: type.icon)
                        .font(.title3)
                        .foregroundStyle(type.color)
                }

                // Type name
                Text(type.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // Distance
                if let (_, distance) = nearest {
                    Text(formatDistance(distance))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(nearest == nil)
        .opacity(nearest == nil ? 0.5 : 1)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 100 {
            return "\(Int(meters))m"
        } else if meters < 1000 {
            let rounded = (Int(meters) / 50) * 50
            return "\(rounded)m"
        } else {
            let km = meters / 1000
            return String(format: "%.1fkm", km)
        }
    }
}

// MARK: - Compact Nearest Widget (for bottom of map)
struct CompactNearestWidget: View {
    let type: FacilityType
    let distance: Double?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.body)
                    .foregroundStyle(type.color)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Nearest \(type.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let distance = distance {
                        Text(formatDistance(distance))
                            .font(.caption)
                            .fontWeight(.semibold)
                    } else {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 100 {
            return "\(Int(meters))m"
        } else if meters < 1000 {
            return "\(Int(meters / 10) * 10)m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}

#Preview {
    VStack {
        NearestFacilityView(
            userLocation: CLLocationCoordinate2D(latitude: 36.27, longitude: -115.01),
            onNavigate: { _ in }
        )

        CompactNearestWidget(
            type: .water,
            distance: 120,
            onTap: {}
        )
    }
}
