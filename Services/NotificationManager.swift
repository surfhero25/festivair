import Foundation
import UserNotifications

/// Manages local and push notifications for set time alerts
final class NotificationManager: ObservableObject {

    // MARK: - Published State
    @Published private(set) var isAuthorized = false
    @Published private(set) var pendingNotifications: Int = 0

    // MARK: - Configuration
    private let defaultLeadTime: TimeInterval = 10 * 60 // 10 minutes before set

    // MARK: - Init
    init() {
        checkAuthorizationStatus()
    }

    // MARK: - Public API

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await MainActor.run {
                isAuthorized = granted
            }
            return granted
        } catch {
            print("[Notifications] Auth error: \(error)")
            return false
        }
    }

    func scheduleSetTimeNotification(
        for setTime: SetTime,
        stageName: String,
        leadTime: TimeInterval? = nil
    ) async {
        guard isAuthorized else { return }

        let notificationTime = setTime.startTime.addingTimeInterval(-(leadTime ?? defaultLeadTime))

        // Don't schedule if already past
        guard notificationTime > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(setTime.artistName) starting soon!"
        content.body = "\(stageName) in \(Int((leadTime ?? defaultLeadTime) / 60)) minutes"
        content.sound = .default
        content.categoryIdentifier = "SET_TIME_REMINDER"

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: notificationTime
            ),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "settime-\(setTime.id.uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[Notifications] Scheduled: \(setTime.artistName) at \(notificationTime)")
            await updatePendingCount()
        } catch {
            print("[Notifications] Schedule error: \(error)")
        }
    }

    func cancelSetTimeNotification(for setTime: SetTime) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["settime-\(setTime.id.uuidString)"]
        )
        Task { await updatePendingCount() }
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        pendingNotifications = 0
    }

    // MARK: - Squad Notifications

    func sendSquadMemberLowBattery(memberName: String, batteryLevel: Int) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(memberName)'s battery is low"
        content.body = "\(batteryLevel)% remaining - they may go offline soon"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "battery-\(memberName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Immediate
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    func sendSquadMemberWentOffline(memberName: String) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(memberName) went offline"
        content.body = "Last location saved. Tap to see on map."
        content.sound = .default
        content.categoryIdentifier = "MEMBER_OFFLINE"

        let request = UNNotificationRequest(
            identifier: "offline-\(memberName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Private Helpers

    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    private func updatePendingCount() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        await MainActor.run {
            pendingNotifications = pending.count
        }
    }
}

// MARK: - Notification Categories
extension NotificationManager {

    static func registerCategories() {
        let viewMapAction = UNNotificationAction(
            identifier: "VIEW_MAP",
            title: "View on Map",
            options: .foreground
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )

        let setTimeCategory = UNNotificationCategory(
            identifier: "SET_TIME_REMINDER",
            actions: [viewMapAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let memberOfflineCategory = UNNotificationCategory(
            identifier: "MEMBER_OFFLINE",
            actions: [viewMapAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            setTimeCategory,
            memberOfflineCategory
        ])
    }
}
