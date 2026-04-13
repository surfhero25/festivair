import Foundation
import Security

/// Helper for storing sensitive data in Keychain (persists across app reinstalls)
enum KeychainHelper {

    private static let service = "com.festivair.app"

    enum Key: String {
        case userId = "userId"
        case displayName = "displayName"
        case emoji = "emoji"
        case appleUserIdentifier = "appleUserIdentifier"  // Sign in with Apple ID
        case appleEmail = "appleEmail"  // Email from Apple (may be relay)
        case squadSecret        // 256-bit AES key for current squad
        case currentSquadId     // Squad ID (moved from UserDefaults)
        case currentJoinCode    // Join code (moved from UserDefaults)
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
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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

    // MARK: - Data (binary)

    static func saveData(_ data: Data, for key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func loadData(for key: Key) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
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
}
