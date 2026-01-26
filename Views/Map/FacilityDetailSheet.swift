import SwiftUI
import CoreLocation

/// Detail sheet for a selected facility
struct FacilityDetailSheet: View {
    let facility: Facility
    let distance: Double?
    let onNavigate: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon and type
                ZStack {
                    Circle()
                        .fill(facility.type.color.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: facility.type.icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(facility.type.color)
                }

                // Info
                VStack(spacing: 8) {
                    Text(facility.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(facility.type.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let distance = distance {
                        Text(formatDistance(distance))
                            .font(.headline)
                            .foregroundStyle(facility.type.color)
                    }

                    // Open status
                    HStack {
                        Circle()
                            .fill(facility.isCurrentlyOpen ? .green : .red)
                            .frame(width: 8, height: 8)

                        Text(facility.isCurrentlyOpen ? "Open" : "Closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                }

                // Description if available
                if let description = facility.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Navigate button
                Button {
                    onNavigate()
                    dismiss()
                } label: {
                    Label("Navigate Here", systemImage: "location.north.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(facility.type.color)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle(facility.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 10 {
            return "You're here!"
        } else if meters < 100 {
            return "\(Int(meters))m away"
        } else if meters < 1000 {
            let rounded = (Int(meters) / 10) * 10
            return "\(rounded)m away"
        } else {
            let km = meters / 1000
            return String(format: "%.1fkm away", km)
        }
    }
}

#Preview {
    FacilityDetailSheet(
        facility: Facility(
            name: "Water Station 1",
            type: .water,
            latitude: 36.27,
            longitude: -115.01,
            description: "Free water refill station. Bring your own bottle!",
            venueId: UUID()
        ),
        distance: 150,
        onNavigate: {}
    )
}
