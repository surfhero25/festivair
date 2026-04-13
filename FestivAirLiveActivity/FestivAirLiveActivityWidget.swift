import ActivityKit
import WidgetKit
import SwiftUI

struct FestivAirLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FestivAirActivityAttributes.self) { context in
            // Lock Screen / StandBy presentation
            LockScreenView(state: context.state, squadName: context.attributes.squadName)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    expandedCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(state: context.state, squadName: context.attributes.squadName)
                }
            } compactLeading: {
                // Compact left side
                compactLeading(state: context.state)
            } compactTrailing: {
                // Compact right side
                compactTrailing(state: context.state)
            } minimal: {
                // Minimal (when competing with other Live Activities)
                minimalView(state: context.state)
            }
        }
    }

    // MARK: - Compact Views (Dynamic Island pill)

    @ViewBuilder
    private func compactLeading(state: FestivAirActivityAttributes.ContentState) -> some View {
        switch state.mode {
        case .navigate:
            Text(state.directionArrow)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.purple)
        case .sos:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .ambient:
            Image(systemName: "person.3.fill")
                .font(.caption)
                .foregroundStyle(.purple)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func compactTrailing(state: FestivAirActivityAttributes.ContentState) -> some View {
        switch state.mode {
        case .navigate:
            Text(state.distanceText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        case .sos:
            Text("SOS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.red)
        case .ambient:
            Text(state.targetName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Minimal View

    @ViewBuilder
    private func minimalView(state: FestivAirActivityAttributes.ContentState) -> some View {
        switch state.mode {
        case .navigate:
            Text(state.directionArrow)
                .font(.title3)
                .foregroundStyle(.purple)
        case .sos:
            Image(systemName: "sos")
                .foregroundStyle(.red)
        default:
            Image(systemName: "person.3.fill")
                .font(.caption2)
                .foregroundStyle(.purple)
        }
    }

    // MARK: - Expanded Views (Dynamic Island expanded)

    @ViewBuilder
    private func expandedLeading(state: FestivAirActivityAttributes.ContentState) -> some View {
        switch state.mode {
        case .navigate:
            Text(state.directionArrow)
                .font(.system(size: 36))
                .fontWeight(.bold)
                .foregroundStyle(.purple)
        case .sos:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.red)
        default:
            Image(systemName: "person.3.fill")
                .font(.title2)
                .foregroundStyle(.purple)
        }
    }

    @ViewBuilder
    private func expandedTrailing(state: FestivAirActivityAttributes.ContentState) -> some View {
        if state.mode == .navigate {
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.distanceText)
                    .font(.title3)
                    .fontWeight(.semibold)
                if state.isArrived {
                    Text("Arrived!")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    @ViewBuilder
    private func expandedCenter(state: FestivAirActivityAttributes.ContentState) -> some View {
        switch state.mode {
        case .navigate:
            Text("Finding \(state.targetName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .sos:
            Text("SOS Emergency")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
        case .ambient:
            Text("Squad Connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func expandedBottom(state: FestivAirActivityAttributes.ContentState, squadName: String) -> some View {
        switch state.mode {
        case .navigate:
            HStack {
                Image(systemName: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text(squadName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !state.isArrived {
                    Text("Live")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                }
            }
        case .sos:
            HStack {
                if let name = state.sosMemberName {
                    Text("\(name) needs help")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("Tap to open")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.red)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        default:
            HStack {
                Text(squadName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let state: FestivAirActivityAttributes.ContentState
    let squadName: String

    var body: some View {
        switch state.mode {
        case .navigate:
            navigationLockScreen
        case .sos:
            sosLockScreen
        case .ambient:
            ambientLockScreen
        case .idle:
            EmptyView()
        }
    }

    private var navigationLockScreen: some View {
        HStack(spacing: 16) {
            // Direction arrow
            Text(state.directionArrow)
                .font(.system(size: 40))
                .fontWeight(.bold)
                .foregroundStyle(.purple)
                .frame(width: 56)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text("Finding \(state.targetName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(state.distanceText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(state.isArrived ? .green : .primary)
            }

            Spacer()

            // Squad badge
            VStack(spacing: 2) {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text("Live")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var sosLockScreen: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("SOS Emergency")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                if let name = state.sosMemberName {
                    Text("\(name) needs help")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            Spacer()

            Text("Open")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white.opacity(0.25))
                .clipShape(Capsule())
        }
        .padding(16)
        .background(.red)
    }

    private var ambientLockScreen: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.title3)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text(squadName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(state.targetName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }
}
