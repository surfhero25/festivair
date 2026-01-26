import SwiftUI

/// Map annotation view for facility locations
struct FacilityAnnotationView: View {
    let facility: Facility
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            // Facility icon
            ZStack {
                Circle()
                    .fill(facility.type.color.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: facility.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(facility.type.color)
            }
            .background(
                Circle()
                    .fill(.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            )
            .overlay(
                Circle()
                    .stroke(isSelected ? facility.type.color : .clear, lineWidth: 2)
                    .frame(width: 44, height: 44)
            )

            // Label (only show when selected or for important facilities)
            if isSelected || facility.type == .medical || facility.type == .exit {
                Text(facility.type.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
        .onTapGesture(perform: onTap)
    }
}

/// Compact facility marker for dense maps
struct CompactFacilityMarker: View {
    let type: FacilityType

    var body: some View {
        ZStack {
            Circle()
                .fill(type.color)
                .frame(width: 24, height: 24)

            Text(type.emoji)
                .font(.caption2)
        }
        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
    }
}

#Preview {
    VStack(spacing: 30) {
        HStack(spacing: 20) {
            FacilityAnnotationView(
                facility: Facility(name: "Water 1", type: .water, latitude: 0, longitude: 0, venueId: UUID()),
                isSelected: false,
                onTap: {}
            )

            FacilityAnnotationView(
                facility: Facility(name: "Medical", type: .medical, latitude: 0, longitude: 0, venueId: UUID()),
                isSelected: true,
                onTap: {}
            )

            FacilityAnnotationView(
                facility: Facility(name: "Bar", type: .bar, latitude: 0, longitude: 0, venueId: UUID()),
                isSelected: false,
                onTap: {}
            )
        }

        HStack(spacing: 10) {
            ForEach(FacilityType.quickAccess, id: \.self) { type in
                CompactFacilityMarker(type: type)
            }
        }
    }
    .padding(50)
}
