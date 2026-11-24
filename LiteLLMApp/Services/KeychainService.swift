import Foundation
import Security

/// Stockage sécurisé dans le trousseau macOS.
///
/// Chaque accès au trousseau peut afficher une demande de mot de passe de session : les
/// valeurs sont donc gardées en mémoire après la première lecture, et ne sont réécrites que
/// si elles changent vraiment.
public enum KeychainService: Sendable {
    private static let service = "com.litellm.app"

    public static let apiKeyAccount = "litellm-api-key"
    public static let masterKeyAccount = "litellm-master-key"

    /// Cache mémoire par compte ; `.some(nil)` = absence connue (évite de relire le trousseau).
    nonisolated(unsafe) private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func save(account: String, value: String) throws {
        lock.lock(); defer { lock.unlock() }
        if case .some(.some(let cached)) = cache[account], cached == value { return }
        try write(account: account, value: value)
        cache[account] = .some(value)
    }

    public static func load(account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[account] { return cached }
        let value = read(account: account)
        cache[account] = .some(value)
        return value
    }

    public static func delete(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        if case .some(.none) = cache[account] { return }
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        cache[account] = .some(nil)
    }

    // MARK: - Accès bruts au trousseau

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Supprime puis recrée l'entrée : elle appartient alors à la version actuelle de l'app.
    private static func write(account: String, value: String) throws {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = query.merging([
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]) { _, new in new }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    // MARK: - Migration

    /// Les entrées créées par d'anciennes versions (signature ad hoc, différente à chaque build)
    /// redemandent le mot de passe à chaque lancement. On les recrée une fois avec l'app
    /// actuelle (signature stable) : macOS ne redemande plus rien ensuite.
    public static func migrateLegacyItemsIfNeeded() {
        let flag = "keychainItemsMigratedToSignedApp"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        lock.lock(); defer { lock.unlock() }
        for account in [apiKeyAccount, masterKeyAccount] {
            if let value = read(account: account) {
                try? write(account: account, value: value)
                cache[account] = .some(value)
            } else {
                cache[account] = .some(nil)
            }
        }
        UserDefaults.standard.set(true, forKey: flag)
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
