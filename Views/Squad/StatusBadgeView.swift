import SwiftUI

/// Compact badge showing a user's current status
struct StatusBadgeView: View {
    let status: UserStatus
    var compact: Bool = false

    var body: some View {
        if status.isActive {
            HStack(spacing: 4) {
                if let preset = status.preset {
                    Image(systemName: preset.icon)
                        .font(compact ? .caption2 : .caption)
                } else {
                    Image(systemName: "bubble.left")
                        .font(compact ? .caption2 : .caption)
                }

                if !compact {
                    Text(status.displayText)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(status.displayText)")
        }
    }

    private var statusColor: Color {
        guard let preset = status.preset else { return .purple }

        switch preset.category {
        case .moving: return .blue
        case .activity: return .orange
        case .needs: return .red
        case .squad: return .purple
        case .waiting: return .gray
        }
    }
}

/// Larger status display for member details
struct StatusDetailView: View {
    let status: UserStatus

    private var statusIcon: String {
        status.preset?.icon ?? "bubble.left"
    }

    private var statusColor: Color {
        guard let preset = status.preset else { return .purple }
        switch preset.category {
        case .moving: return .blue
        case .activity: return .orange
        case .needs: return .red
        case .squad: return .purple
        case .waiting: return .gray
        }
    }

    var body: some View {
        if status.isActive {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.displayText)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(timeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var timeText: String {
        let elapsed = Date().timeIntervalSince(status.setAt)

        if elapsed < 60 {
            return "Just now"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(elapsed / 3600)
            return "\(hours)h ago"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StatusBadgeView(status: .preset(.atTheBar))
        StatusBadgeView(status: .preset(.headingToMainStage))
        StatusBadgeView(status: .preset(.needsWater))
        StatusBadgeView(status: .preset(.lookingForGroup))
        StatusBadgeView(status: .preset(.inLine))

        StatusBadgeView(status: .preset(.atTheBar), compact: true)

        StatusDetailView(status: .preset(.atTheBar))
        StatusDetailView(status: .custom("Meeting by the ferris wheel"))
    }
    .padding()
}
