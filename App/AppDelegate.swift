import UIKit
import UserNotifications
import BackgroundTasks
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for push notifications
        registerForPushNotifications()

        // Register background tasks
        registerBackgroundTasks()

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // MARK: - Push Notifications

    private func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        #if DEBUG
        print("[Push] Device token registered")
        #endif
        _ = token  // Would save this token for push notifications
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[Push] Failed to register: \(error)")
        #endif
    }

    // MARK: - CloudKit Push Notifications

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Check if this is a CloudKit notification
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            completionHandler(.noData)
            return
        }

        if let queryNotification = notification as? CKQueryNotification {
            let subscriptionID = queryNotification.subscriptionID ?? ""

            if subscriptionID.hasPrefix("message-") {
                // New message — tell ChatViewModel to fetch
                NotificationCenter.default.post(name: .cloudKitMessageReceived, object: nil)
                completionHandler(.newData)
            } else if subscriptionID.hasPrefix("location-") {
                // Location update — handled by mesh, but good to have
                completionHandler(.newData)
            } else {
                completionHandler(.noData)
            }
        } else {
            completionHandler(.noData)
        }
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.festivair.mesh-sync",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handleMeshSyncTask(processingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.festivair.location-update",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleLocationUpdateTask(refreshTask)
        }
    }

    private func handleMeshSyncTask(_ task: BGProcessingTask) {
        // Schedule next task
        scheduleBackgroundSync()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Perform mesh sync
        Task { @MainActor in
            await AppState.shared?.meshCoordinator.handleBackgroundTask()
            task.setTaskCompleted(success: true)
        }
    }

    private func handleLocationUpdateTask(_ task: BGAppRefreshTask) {
        scheduleLocationUpdate()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task { @MainActor in
            await AppState.shared?.meshCoordinator.handleBackgroundTask()
            task.setTaskCompleted(success: true)
        }
    }

    func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: "com.festivair.mesh-sync")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[BG] Failed to schedule sync: \(error)")
            #endif
        }
    }

    func scheduleLocationUpdate() {
        let request = BGAppRefreshTaskRequest(identifier: "com.festivair.location-update")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[BG] Failed to schedule location: \(error)")
            #endif
        }
    }

    // MARK: - URL Handling

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // Handle festivair://squad/CODE URLs
        guard url.scheme == "festivair",
              url.host == "squad",
              let code = url.pathComponents.last else {
            return false
        }

        // Validate join code format (codeLength chars, alphanumeric excluding confusing chars)
        let validChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard normalizedCode.count == Constants.Squad.codeLength,
              normalizedCode.allSatisfy({ validChars.contains($0) }) else {
            #if DEBUG
            print("[URL] Invalid squad code format")
            #endif
            return false
        }

        // Post notification to join squad
        NotificationCenter.default.post(
            name: .joinSquadFromURL,
            object: nil,
            userInfo: ["code": normalizedCode]
        )

        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let categoryIdentifier = response.notification.request.content.categoryIdentifier

        switch response.actionIdentifier {
        case "VIEW_MAP":
            // Navigate to map view
            NotificationCenter.default.post(name: .navigateToMap, object: nil, userInfo: userInfo)
        case "OPEN_CHAT", UNNotificationDefaultActionIdentifier:
            // User tapped on notification - if it's a chat notification, navigate to chat and clear badge
            if categoryIdentifier == "CHAT_MESSAGE" {
                NotificationCenter.default.post(name: .navigateToChat, object: nil, userInfo: userInfo)
                // Clear badge when user opens chat from notification
                Task {
                    try? await UNUserNotificationCenter.current().setBadgeCount(0)
                }
            }
        default:
            break
        }

        completionHandler()
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let joinSquadFromURL = Notification.Name("FestivAir.JoinSquadFromURL")
    static let navigateToMap = Notification.Name("FestivAir.NavigateToMap")
    static let navigateToChat = Notification.Name("FestivAir.NavigateToChat")
    static let didLeaveSquad = Notification.Name("FestivAir.DidLeaveSquad")
    static let cloudKitMessageReceived = Notification.Name("FestivAir.CloudKitMessageReceived")
}
