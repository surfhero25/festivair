import Foundation
import ActivityKit

/// Manages Live Activities for navigation and SOS on Dynamic Island / Lock Screen.
@MainActor
final class LiveActivityManager: ObservableObject {

    // MARK: - State

    @Published private(set) var isActivityActive: Bool = false
    private var currentActivity: Activity<FestivAirActivityAttributes>?

    // MARK: - Start Activity

    /// Starts a navigation Live Activity
    func startNavigation(squadName: String, targetName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            #if DEBUG
            print("[LiveActivity] Activities not enabled")
            #endif
            return
        }

        let attributes = FestivAirActivityAttributes(squadName: squadName)
        let state = FestivAirActivityAttributes.ContentState(
            mode: .navigate,
            targetName: targetName,
            distanceMeters: nil,
            bearingDegrees: nil,
            isArrived: false,
            isSOSActive: false,
            sosMemberName: nil
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            isActivityActive = true
            #if DEBUG
            print("[LiveActivity] Started navigation to \(targetName)")
            #endif
        } catch {
            #if DEBUG
            print("[LiveActivity] Failed to start: \(error)")
            #endif
        }
    }

    /// Starts an ambient "squad connected" Live Activity
    func startAmbient(squadName: String, memberCount: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = FestivAirActivityAttributes(squadName: squadName)
        let state = FestivAirActivityAttributes.ContentState(
            mode: .ambient,
            targetName: "\(memberCount) members",
            distanceMeters: nil,
            bearingDegrees: nil,
            isArrived: false,
            isSOSActive: false,
            sosMemberName: nil
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            isActivityActive = true
        } catch {
            #if DEBUG
            print("[LiveActivity] Failed to start ambient: \(error)")
            #endif
        }
    }

    // MARK: - Update Activity

    /// Updates navigation bearing and distance (called every 3 seconds during NAVIGATE)
    func updateNavigation(distanceMeters: Double, bearingDegrees: Double, isArrived: Bool) {
        guard let activity = currentActivity else { return }

        let state = FestivAirActivityAttributes.ContentState(
            mode: .navigate,
            targetName: activity.content.state.targetName,
            distanceMeters: distanceMeters,
            bearingDegrees: bearingDegrees,
            isArrived: isArrived,
            isSOSActive: false,
            sosMemberName: nil
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }

        // Auto-dismiss on arrival
        if isArrived {
            Task {
                try? await Task.sleep(for: .seconds(3))
                await endActivity()
            }
        }
    }

    /// Shows SOS alert on Dynamic Island (overrides everything)
    func showSOS(squadName: String, memberName: String) {
        // End any existing activity first
        Task {
            await endActivity()

            let attributes = FestivAirActivityAttributes(squadName: squadName)
            let state = FestivAirActivityAttributes.ContentState(
                mode: .sos,
                targetName: memberName,
                distanceMeters: nil,
                bearingDegrees: nil,
                isArrived: false,
                isSOSActive: true,
                sosMemberName: memberName
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
                currentActivity = activity
                isActivityActive = true
            } catch {
                #if DEBUG
                print("[LiveActivity] Failed to start SOS: \(error)")
                #endif
            }
        }
    }

    // MARK: - End Activity

    func endActivity() async {
        guard let activity = currentActivity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
        isActivityActive = false
    }

    func endActivitySync() {
        Task {
            await endActivity()
        }
    }
}
