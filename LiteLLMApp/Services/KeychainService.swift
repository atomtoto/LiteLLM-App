import Foundation
import Security

/// Stockage sécurisé dans le trousseau macOS.
public enum KeychainService: Sendable {
    private static let service = "com.litellm.app"

    public static let apiKeyAccount = "litellm-api-key"
    public static let masterKeyAccount = "litellm-master-key"

    public static func save(account: String, value: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = query.merging([
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]) { _, new in new }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Clés pratiques

    public static func saveAPIKey(_ key: String) throws { try save(account: apiKeyAccount, value: key) }
    public static func loadAPIKey() -> String? { load(account: apiKeyAccount) }
    public static func deleteAPIKey() throws { try delete(account: apiKeyAccount) }

    public static func saveMasterKey(_ key: String) throws { try save(account: masterKeyAccount, value: key) }
    public static func loadMasterKey() -> String? { load(account: masterKeyAccount) }
}

public enum KeychainError: Error, LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Erreur trousseau (code \(status))."
        }
    }
}
