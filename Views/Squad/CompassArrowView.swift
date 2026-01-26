import SwiftUI
import CoreLocation

/// A compass-style arrow that points toward a target location.
/// Shows distance and proximity feedback as you approach.
struct CompassArrowView: View {
    let targetName: String
    let targetEmoji: String
    let bearing: Double // Bearing to target in degrees
    let distance: Double? // Distance in meters
    let proximityLevel: ProximityHapticsManager.ProximityLevel
    let onDismiss: () -> Void

    @State private var pulseAnimation = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Finding \(targetName)")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // Compass arrow
            ZStack {
                // Outer ring
                Circle()
                    .stroke(proximityColor.opacity(0.3), lineWidth: 4)
                    .frame(width: 180, height: 180)

                // Pulse effect for close proximity
                if proximityLevel >= .near {
                    Circle()
                        .stroke(proximityColor.opacity(pulseAnimation ? 0.0 : 0.5), lineWidth: 2)
                        .frame(width: pulseAnimation ? 200 : 180, height: pulseAnimation ? 200 : 180)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulseAnimation)
                }

                // Direction arrow
                ArrowShape()
                    .fill(proximityColor)
                    .frame(width: 60, height: 100)
                    .rotationEffect(.degrees(bearing))
                    .shadow(color: proximityColor.opacity(0.5), radius: 10)

                // Center dot
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)

                // Target emoji
                Text(targetEmoji)
                    .font(.title)
            }
            .padding()

            // Distance and status
            VStack(spacing: 8) {
                if let distance = distance {
                    Text(formatDistance(distance))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(proximityColor)
                }

                Text(proximityLevel.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Compass bearing
                Text(bearingDirection)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 20)
        .padding()
        .onAppear {
            pulseAnimation = true
        }
    }

    // MARK: - Helpers

    private var proximityColor: Color {
        switch proximityLevel {
        case .far: return .gray
        case .approaching: return .blue
        case .near: return .orange
        case .close: return .purple
        case .veryClose: return .green
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 10 {
            return "Here!"
        } else if meters < 100 {
            return "\(Int(meters))m"
        } else if meters < 1000 {
            let rounded = (Int(meters) / 10) * 10
            return "\(rounded)m"
        } else {
            let km = meters / 1000
            return String(format: "%.1fkm", km)
        }
    }

    private var bearingDirection: String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((bearing + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return "Head \(directions[index])"
    }
}

// MARK: - Arrow Shape
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let midX = rect.midX
        let width = rect.width
        let height = rect.height

        // Arrow pointing up
        path.move(to: CGPoint(x: midX, y: 0)) // Top point
        path.addLine(to: CGPoint(x: midX + width * 0.4, y: height * 0.4)) // Right wing
        path.addLine(to: CGPoint(x: midX + width * 0.15, y: height * 0.35)) // Right indent
        path.addLine(to: CGPoint(x: midX + width * 0.15, y: height)) // Right bottom
        path.addLine(to: CGPoint(x: midX - width * 0.15, y: height)) // Left bottom
        path.addLine(to: CGPoint(x: midX - width * 0.15, y: height * 0.35)) // Left indent
        path.addLine(to: CGPoint(x: midX - width * 0.4, y: height * 0.4)) // Left wing
        path.closeSubpath()

        return path
    }
}

// MARK: - Compact Compass (for map overlay)
struct CompactCompassView: View {
    let targetName: String
    let bearing: Double
    let distance: Double?
    let proximityLevel: ProximityHapticsManager.ProximityLevel
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Arrow indicator
            ZStack {
                Circle()
                    .fill(proximityColor.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: "location.north.fill")
                    .font(.title2)
                    .foregroundStyle(proximityColor)
                    .rotationEffect(.degrees(bearing))
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text("Finding \(targetName)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    if let distance = distance {
                        Text(formatDistance(distance))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(proximityColor)
                    }
                    Text(proximityLevel.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Expand button
            Button(action: onTap) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Dismiss
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var proximityColor: Color {
        switch proximityLevel {
        case .far: return .gray
        case .approaching: return .blue
        case .near: return .orange
        case .close: return .purple
        case .veryClose: return .green
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 10 {
            return "Here!"
        } else if meters < 100 {
            return "\(Int(meters))m"
        } else if meters < 1000 {
            let rounded = (Int(meters) / 10) * 10
            return "\(rounded)m"
        } else {
            let km = meters / 1000
            return String(format: "%.1fkm", km)
        }
    }
}

#Preview {
    VStack {
        CompassArrowView(
            targetName: "Alex",
            targetEmoji: "🎸",
            bearing: 45,
            distance: 150,
            proximityLevel: .approaching,
            onDismiss: {}
        )
        .frame(height: 400)

        CompactCompassView(
            targetName: "Alex",
            bearing: 45,
            distance: 150,
            proximityLevel: .approaching,
            onTap: {},
            onDismiss: {}
        )
        .padding()
    }
}
