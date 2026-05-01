import Foundation
import Security
import os.log

struct AppSecretStore: Sendable {
    let loadValue: @Sendable (String) -> String?
    let saveValue: @Sendable (String, String) -> Void
    let saveIfMissingValue: @Sendable (String, String) -> Bool

    func load(key: String) -> String? {
        loadValue(key)
    }

    func save(key: String, value: String) {
        saveValue(key, value)
    }
    
    @discardableResult
    func saveIfMissing(key: String, value: String) -> Bool {
        saveIfMissingValue(key, value)
    }

    static let keychain = AppSecretStore(
        loadValue: { KeychainHelper.load(key: $0) },
        saveValue: { key, value in
            KeychainHelper.save(key: key, value: value)
        },
        saveIfMissingValue: { key, value in
            KeychainHelper.saveIfMissing(key: key, value: value)
        }
    )

    static let ephemeral = AppSecretStore(
        loadValue: { _ in nil },
        saveValue: { _, _ in },
        saveIfMissingValue: { _, _ in true }
    )
}

struct SettingsStorage {
    let defaults: UserDefaults
    let secretStore: AppSecretStore
    let defaultNotesDirectory: URL
    let runMigrations: Bool

    static func live(defaults: UserDefaults = .standard) -> SettingsStorage {
        SettingsStorage(
            defaults: defaults,
            secretStore: .keychain,
            defaultNotesDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/OpenOats"),
            runMigrations: true
        )
    }
}

/// Backward-compatible alias for existing test code.
typealias AppSettingsStorage = SettingsStorage

// MARK: - Keychain Helper

enum KeychainHelper {
    private static let service = "com.openoats.app"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else {
            os_log("Keychain save failed: unable to encode value for key %{public}@", log: .default, type: .error, key)
            return
        }
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            os_log("Keychain save failed for key %{public}@: status %{public}d", log: .default, type: .error, key, status)
        }
    }

    static func saveIfMissing(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            os_log("Keychain saveIfMissing failed: unable to encode value for key %{public}@", log: .default, type: .error, key)
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        } else if status == errSecDuplicateItem {
            // Item already exists - this is acceptable for "save if missing" semantics
            return true
        } else {
            os_log("Keychain saveIfMissing failed for key %{public}@: status %{public}d", log: .default, type: .error, key, status)
            return false
        }
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            // Success or item didn't exist (idempotent)
            return true
        } else {
            os_log("Keychain delete failed for key %{public}@: status %{public}d", log: .default, type: .error, key, status)
            return false
        }
    }
}
