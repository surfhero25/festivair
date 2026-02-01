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
            DebugLogger.error("Auth error: \(error)", category: "Notifications")
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
            DebugLogger.success("Scheduled: \(setTime.artistName) at \(notificationTime)", category: "Notifications")
            await updatePendingCount()
        } catch {
            DebugLogger.error("Schedule error: \(error)", category: "Notifications")
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

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            DebugLogger.error("Failed to send battery warning: \(error)", category: "Notifications")
        }
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

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            DebugLogger.error("Failed to send offline notification: \(error)", category: "Notifications")
        }
    }

    // MARK: - Chat Notifications

    func sendNewMessageNotification(senderName: String, messageText: String, squadId: String) async {
        // Double-check authorization status (in case it wasn't set on init)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = settings.authorizationStatus == .authorized

        guard authorized else {
            DebugLogger.warning("Not authorized for notifications (status: \(settings.authorizationStatus.rawValue))", category: "Notifications")
            return
        }

        // Update cached value
        await MainActor.run { isAuthorized = true }

        // Don't send if notifications for squad messages are explicitly disabled
        // Default to true if not set (object(forKey:) returns nil for unset keys)
        if let notifySquadValue = UserDefaults.standard.object(forKey: "FestivAir.NotifySquad") as? Bool,
           notifySquadValue == false {
            DebugLogger.info("Squad notifications disabled by user", category: "Notifications")
            return
        }

        DebugLogger.info("Preparing chat notification from \(senderName)", category: "Notifications")

        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = messageText
        content.sound = .default
        content.categoryIdentifier = "CHAT_MESSAGE"
        content.threadIdentifier = "squad-\(squadId)"
        content.userInfo = ["squadId": squadId]

        // Set badge count
        await incrementBadge()

        let request = UNNotificationRequest(
            identifier: "chat-\(UUID().uuidString)",
            content: content,
            trigger: nil // Immediate
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            DebugLogger.success("Sent chat notification from \(senderName)", category: "Notifications")
        } catch {
            DebugLogger.error("Failed to send chat notification: \(error)", category: "Notifications")
        }
    }

    func clearChatBadge() {
        Task { @MainActor in
            UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }

    private func incrementBadge() async {
        let current = await UNUserNotificationCenter.current().deliveredNotifications().count
        try? await UNUserNotificationCenter.current().setBadgeCount(current + 1)
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

        let openChatAction = UNNotificationAction(
            identifier: "OPEN_CHAT",
            title: "Open Chat",
            options: .foreground
        )

        let chatMessageCategory = UNNotificationCategory(
            identifier: "CHAT_MESSAGE",
            actions: [openChatAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            setTimeCategory,
            memberOfflineCategory,
            chatMessageCategory
        ])
    }
}
