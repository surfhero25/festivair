import SwiftUI

/// Map annotation view for meetup pins with pulsing animation
struct MeetupPinAnnotationView: View {
    let pin: MeetupPin
    let isSelected: Bool
    let onTap: () -> Void
    let onNavigate: () -> Void
    let onDismiss: () -> Void

    @State private var pulseAnimation = false
    @State private var lastActiveState = true

    var body: some View {
        VStack(spacing: 4) {
            // Pin marker with pulse
            ZStack {
                // Pulse rings
                if pin.isActive {
                    Circle()
                        .stroke(Color.orange.opacity(pulseAnimation ? 0 : 0.5), lineWidth: 2)
                        .frame(width: pulseAnimation ? 60 : 40, height: pulseAnimation ? 60 : 40)
                        .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: pulseAnimation)

                    Circle()
                        .stroke(Color.orange.opacity(pulseAnimation ? 0 : 0.3), lineWidth: 2)
                        .frame(width: pulseAnimation ? 80 : 50, height: pulseAnimation ? 80 : 50)
                        .animation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(0.5), value: pulseAnimation)
                }

                // Main pin
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(pin.isActive ? .orange : .gray)
                    .background(
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 30, height: 30)
                    )
                    .accessibilityLabel("Meetup pin: \(pin.name)")
            }

            // Info label
            VStack(spacing: 2) {
                Text(pin.name)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(pin.timeRemaining)
                    .font(.caption2)
                    .foregroundStyle(pin.isActive ? .orange : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button {
                onNavigate()
            } label: {
                Label("Navigate Here", systemImage: "location.north.fill")
            }

            Button(role: .destructive) {
                onDismiss()
            } label: {
                Label("Remove Pin", systemImage: "trash")
            }
        }
        .onAppear {
            if pin.isActive {
                pulseAnimation = true
            }
        }
        .onChange(of: pin.isActive) { _, isActive in
            // Stop pulse animation when pin expires
            if !isActive && lastActiveState {
                pulseAnimation = false
            }
            lastActiveState = isActive
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meetup pin from \(pin.creatorName): \(pin.name), \(pin.timeRemaining)")
        .accessibilityHint("Double tap to view details, long press for options")
    }
}

// MARK: - Pin Detail Sheet
struct MeetupPinDetailSheet: View {
    let pin: MeetupPin
    let distance: Double?
    let onNavigate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Pin icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)
                }

                // Pin info
                VStack(spacing: 8) {
                    Text(pin.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Dropped by \(pin.creatorName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let distance = distance {
                        Text(formatDistance(distance))
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }

                    Text(pin.timeRemaining)
                        .font(.caption)
                        .foregroundStyle(pin.isActive ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(pin.isActive ? Color.orange.opacity(0.1) : Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        onNavigate()
                        dismiss()
                    } label: {
                        Label("Navigate Here", systemImage: "location.north.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Button(role: .destructive) {
                        onDismiss()
                        dismiss()
                    } label: {
                        Label("Remove Pin", systemImage: "trash")
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .navigationTitle("Meetup Pin")
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
    VStack {
        MeetupPinAnnotationView(
            pin: MeetupPin.create(
                at: .init(latitude: 36.2697, longitude: -115.0078),
                name: "Meet me here!",
                creatorId: "test",
                creatorName: "Alex"
            ),
            isSelected: false,
            onTap: {},
            onNavigate: {},
            onDismiss: {}
        )
    }
    .padding(50)
}
