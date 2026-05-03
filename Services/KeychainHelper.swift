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

    // MARK: - Shared App Identity

    /// The signed-in user's stable ID. Keychain is the source of truth, but
    /// UserDefaults is kept in sync because older app components still read it.
    static var currentUserId: String? {
        if let userId = load(.userId), !userId.isEmpty {
            mirror(userId, toUserDefaultsKey: Constants.UserDefaultsKeys.userId)
            return userId
        }

        if let legacyUserId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId),
           !legacyUserId.isEmpty {
            return legacyUserId
        }

        return nil
    }

    static func saveCurrentUserId(_ userId: String) {
        save(userId, for: .userId)
        mirror(userId, toUserDefaultsKey: Constants.UserDefaultsKeys.userId)
    }

    static func saveCurrentSquad(id: String, joinCode: String, cloudId: String? = nil) {
        save(id, for: .currentSquadId)
        save(joinCode, for: .currentJoinCode)
        mirror(id, toUserDefaultsKey: Constants.UserDefaultsKeys.currentSquadId)
        mirror(joinCode, toUserDefaultsKey: Constants.UserDefaultsKeys.currentJoinCode)
        if let cloudId {
            mirror(cloudId, toUserDefaultsKey: Constants.UserDefaultsKeys.currentCloudSquadId)
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.currentCloudSquadId)
        }
    }

    static func clearCurrentSquad() {
        delete(.currentSquadId)
        delete(.currentJoinCode)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.currentSquadId)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.currentJoinCode)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.currentCloudSquadId)
    }

    static func mirrorIdentityToUserDefaults() {
        if let userId = load(.userId) {
            mirror(userId, toUserDefaultsKey: Constants.UserDefaultsKeys.userId)
        }
        if let displayName = load(.displayName) {
            mirror(displayName, toUserDefaultsKey: Constants.UserDefaultsKeys.displayName)
        }
        if let emoji = load(.emoji) {
            mirror(emoji, toUserDefaultsKey: Constants.UserDefaultsKeys.emoji)
        }
        if let squadId = load(.currentSquadId) {
            mirror(squadId, toUserDefaultsKey: Constants.UserDefaultsKeys.currentSquadId)
        }
        if let joinCode = load(.currentJoinCode) {
            mirror(joinCode, toUserDefaultsKey: Constants.UserDefaultsKeys.currentJoinCode)
        }
    }

    static func clearUserData() {
        delete(.userId)
        delete(.displayName)
        delete(.emoji)
        delete(.appleUserIdentifier)
        delete(.appleEmail)
        delete(.squadSecret)
        clearCurrentSquad()

        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.userId)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.displayName)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.emoji)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.onboarded)
        UserDefaults.standard.removeObject(forKey: "FestivAir.CurrentUserStatus")
    }

    private static func mirror(_ value: String, toUserDefaultsKey key: String) {
        if UserDefaults.standard.string(forKey: key) != value {
            UserDefaults.standard.set(value, forKey: key)
        }
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
        #if DEBUG
        if status != errSecSuccess {
            print("[Keychain] Failed to save \(key.rawValue): \(status)")
        } else {
            print("[Keychain] Saved \(key.rawValue)")
        }
        #endif
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
            #if DEBUG
            print("[Keychain] Already have userId in keychain")
            #endif
            return
        }

        // Try to migrate from UserDefaults
        if let userId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userId) {
            save(userId, for: .userId)
            #if DEBUG
            print("[Keychain] Migrated userId from UserDefaults")
            #endif
        }

        if let displayName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.displayName) {
            save(displayName, for: .displayName)
            #if DEBUG
            print("[Keychain] Migrated displayName from UserDefaults")
            #endif
        }

        if let emoji = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.emoji) {
            save(emoji, for: .emoji)
            #if DEBUG
            print("[Keychain] Migrated emoji from UserDefaults")
            #endif
        }

        mirrorIdentityToUserDefaults()
    }
}
