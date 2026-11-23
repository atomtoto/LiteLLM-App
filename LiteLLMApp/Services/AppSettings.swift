import Foundation

/// Réglages de l'app : persistés dans UserDefaults, sauf la clé API qui vit dans le trousseau.
@MainActor
public final class AppSettings: ObservableObject {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let serverURL = "serverURL"
        static let defaultModel = "defaultModel"
        static let temperature = "temperature"
        static let maxTokens = "maxTokens"
        static let systemPrompt = "systemPrompt"
        static let availableModels = "availableModels"
    }

    @Published public var serverURL: String {
        didSet { Self.defaults.set(serverURL, forKey: Keys.serverURL) }
    }
    /// Clé API : chargée depuis le trousseau, conservée en mémoire uniquement.
    @Published public var apiKey: String = ""
    @Published public var defaultModel: String {
        didSet { Self.defaults.set(defaultModel, forKey: Keys.defaultModel) }
    }
    @Published public var temperature: Double {
        didSet { Self.defaults.set(temperature, forKey: Keys.temperature) }
    }
    @Published public var maxTokens: Int {
        didSet { Self.defaults.set(maxTokens, forKey: Keys.maxTokens) }
    }
    @Published public var systemPrompt: String {
        didSet { Self.defaults.set(systemPrompt, forKey: Keys.systemPrompt) }
    }
    @Published public var availableModels: [String] {
        didSet { Self.defaults.set(availableModels, forKey: Keys.availableModels) }
    }

    public init() {
        let d = Self.defaults
        self.serverURL = d.string(forKey: Keys.serverURL) ?? "http://localhost:4000"
        self.defaultModel = d.string(forKey: Keys.defaultModel) ?? ""
        self.temperature = d.object(forKey: Keys.temperature) as? Double ?? 0.7
        self.maxTokens = d.object(forKey: Keys.maxTokens) as? Int ?? 1024
        self.systemPrompt = d.string(forKey: Keys.systemPrompt) ?? ""
        self.availableModels = d.array(forKey: Keys.availableModels) as? [String] ?? []
        self.apiKey = KeychainService.loadAPIKey() ?? ""
    }

    /// URL de base normalisée (sans slash final), ou nil si invalide.
    public var baseURL: URL? {
        var value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        guard !value.isEmpty, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    public func saveAPIKeyToKeychain() {
        guard !apiKey.isEmpty else { try? KeychainService.deleteAPIKey(); return }
        try? KeychainService.saveAPIKey(apiKey)
    }

    public func makeClient() -> LiteLLMClient? {
        guard let baseURL else { return nil }
        return LiteLLMClient(baseURL: baseURL, apiKey: apiKey.isEmpty ? nil : apiKey)
    }
}
