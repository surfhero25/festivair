import Foundation
import Security

/// Helper for storing sensitive data in Keychain (persists across app reinstalls)
enum KeychainHelper {

    private static let service = "com.festivair.app"

    enum Key: String {
        case userId = "userId"
        case displayName = "displayName"
        case emoji = "emoji"
    }

    // MARK: - Save

    static func save(_ value: String, for key: Key) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item first
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Failed to save \(key.rawValue): \(status)")
        } else {
            print("[Keychain] Saved \(key.rawValue)")
        }
    }

    // MARK: - Load

    static func load(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    // MARK: - Delete

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Migration

    /// Migrate data from UserDefaults to Keychain (call on app launch)
    static func migrateFromUserDefaultsIfNeeded() {
        // Check if we have keychain data already
        if load(.userId) != nil {
            print("[Keychain] Already have userId in keychain")
            return
        }

        // Try to migrate from UserDefaults
        if let userId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId) {
            save(userId, for: .userId)
            print("[Keychain] Migrated userId from UserDefaults")
        }

        if let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) {
            save(displayName, for: .displayName)
            print("[Keychain] Migrated displayName from UserDefaults")
        }

        if let emoji = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.emoji) {
            save(emoji, for: .emoji)
            print("[Keychain] Migrated emoji from UserDefaults")
        }
    }

    /// Restore Keychain data to UserDefaults (for app components that use UserDefaults)
    static func restoreToUserDefaults() {
        if let userId = load(.userId) {
            UserDefaults.standard.set(userId, forKey: Constants.UserDefaultsKeys.userId)
            print("[Keychain] Restored userId to UserDefaults")
        }

        if let displayName = load(.displayName) {
            UserDefaults.standard.set(displayName, forKey: Constants.UserDefaultsKeys.displayName)
            print("[Keychain] Restored displayName to UserDefaults")
        }

        if let emoji = load(.emoji) {
            UserDefaults.standard.set(emoji, forKey: Constants.UserDefaultsKeys.emoji)
            print("[Keychain] Restored emoji to UserDefaults")
        }

        // If we restored any user data, mark as onboarded
        if load(.userId) != nil && load(.displayName) != nil {
            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.onboarded)
            print("[Keychain] Restored onboarded status")
        }

        UserDefaults.standard.synchronize()
    }
}
