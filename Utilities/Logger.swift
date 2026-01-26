import Foundation
import os.log

/// Centralized logging for FestivAir
/// Uses Apple's unified logging system (os.log) for production-ready logging
/// Logs are only visible in Console.app or Xcode debugger, not in App Store builds
enum Log {

    // MARK: - Subsystems

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.festivair"

    // MARK: - Categories

    private static let mesh = Logger(subsystem: subsystem, category: "Mesh")
    private static let cloudKit = Logger(subsystem: subsystem, category: "CloudKit")
    private static let sync = Logger(subsystem: subsystem, category: "Sync")
    private static let location = Logger(subsystem: subsystem, category: "Location")
    private static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    private static let subscription = Logger(subsystem: subsystem, category: "Subscription")
    private static let chat = Logger(subsystem: subsystem, category: "Chat")
    private static let squad = Logger(subsystem: subsystem, category: "Squad")
    private static let parties = Logger(subsystem: subsystem, category: "Parties")
    private static let map = Logger(subsystem: subsystem, category: "Map")
    private static let profile = Logger(subsystem: subsystem, category: "Profile")
    private static let gateway = Logger(subsystem: subsystem, category: "Gateway")
    private static let offlineMap = Logger(subsystem: subsystem, category: "OfflineMap")
    private static let setTimes = Logger(subsystem: subsystem, category: "SetTimes")
    private static let imageCache = Logger(subsystem: subsystem, category: "ImageCache")
    private static let app = Logger(subsystem: subsystem, category: "App")
    private static let general = Logger(subsystem: subsystem, category: "General")

    // MARK: - Mesh Network

    static func meshInfo(_ message: String) {
        mesh.info("\(message)")
    }

    static func meshError(_ message: String) {
        mesh.error("\(message)")
    }

    static func meshDebug(_ message: String) {
        mesh.debug("\(message)")
    }

    // MARK: - CloudKit

    static func cloudKitInfo(_ message: String) {
        cloudKit.info("\(message)")
    }

    static func cloudKitError(_ message: String) {
        cloudKit.error("\(message)")
    }

    // MARK: - Sync

    static func syncInfo(_ message: String) {
        sync.info("\(message)")
    }

    static func syncError(_ message: String) {
        sync.error("\(message)")
    }

    // MARK: - Location

    static func locationInfo(_ message: String) {
        location.info("\(message)")
    }

    static func locationError(_ message: String) {
        location.error("\(message)")
    }

    // MARK: - Notifications

    static func notificationInfo(_ message: String) {
        notifications.info("\(message)")
    }

    static func notificationError(_ message: String) {
        notifications.error("\(message)")
    }

    // MARK: - Subscription

    static func subscriptionInfo(_ message: String) {
        subscription.info("\(message)")
    }

    static func subscriptionError(_ message: String) {
        subscription.error("\(message)")
    }

    // MARK: - Chat

    static func chatInfo(_ message: String) {
        chat.info("\(message)")
    }

    static func chatError(_ message: String) {
        chat.error("\(message)")
    }

    // MARK: - Squad

    static func squadInfo(_ message: String) {
        squad.info("\(message)")
    }

    static func squadError(_ message: String) {
        squad.error("\(message)")
    }

    // MARK: - Parties

    static func partiesInfo(_ message: String) {
        parties.info("\(message)")
    }

    static func partiesError(_ message: String) {
        parties.error("\(message)")
    }

    // MARK: - Map

    static func mapInfo(_ message: String) {
        map.info("\(message)")
    }

    static func mapError(_ message: String) {
        map.error("\(message)")
    }

    // MARK: - Profile

    static func profileInfo(_ message: String) {
        profile.info("\(message)")
    }

    static func profileError(_ message: String) {
        profile.error("\(message)")
    }

    // MARK: - Gateway

    static func gatewayInfo(_ message: String) {
        gateway.info("\(message)")
    }

    static func gatewayError(_ message: String) {
        gateway.error("\(message)")
    }

    // MARK: - Offline Maps

    static func offlineMapInfo(_ message: String) {
        offlineMap.info("\(message)")
    }

    static func offlineMapError(_ message: String) {
        offlineMap.error("\(message)")
    }

    // MARK: - Set Times

    static func setTimesInfo(_ message: String) {
        setTimes.info("\(message)")
    }

    static func setTimesError(_ message: String) {
        setTimes.error("\(message)")
    }

    // MARK: - Image Cache

    static func imageCacheInfo(_ message: String) {
        imageCache.info("\(message)")
    }

    static func imageCacheError(_ message: String) {
        imageCache.error("\(message)")
    }

    // MARK: - App

    static func appInfo(_ message: String) {
        app.info("\(message)")
    }

    static func appError(_ message: String) {
        app.error("\(message)")
    }

    // MARK: - General

    static func info(_ message: String) {
        general.info("\(message)")
    }

    static func error(_ message: String) {
        general.error("\(message)")
    }

    static func debug(_ message: String) {
        general.debug("\(message)")
    }
}
