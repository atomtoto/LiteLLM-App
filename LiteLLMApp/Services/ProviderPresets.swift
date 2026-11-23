import Foundation

// MARK: - Presets fournisseurs

/// Un modèle connu d'un fournisseur (id LiteLLM + libellé lisible).
public struct KnownModel: Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public init(id: String, label: String? = nil) {
        self.id = id
        self.label = label ?? id
    }
}

/// Un fournisseur d'IA préconfiguré pour LiteLLM.
public struct ProviderPreset: Identifiable, Hashable, Sendable {
    public let id: String
    /// Préfixe LiteLLM, ex. « openai/ » — le modèle complet est « préfixe + id du modèle ».
    public let litellmPrefix: String
    public let displayName: String
    public let systemImage: String
    public let knownModels: [KnownModel]
    /// API base par défaut (Ollama, Azure…), vide sinon.
    public let defaultAPIBase: String
    public let requiresAPIKey: Bool
    /// Préfixes de clé permettant de détecter le fournisseur automatiquement.
    public let keyPrefixes: [String]
    /// Page où créer une clé API.
    public let keyHelpURL: URL?

    public init(id: String, litellmPrefix: String, displayName: String, systemImage: String,
                knownModels: [KnownModel], defaultAPIBase: String = "", requiresAPIKey: Bool = true,
                keyPrefixes: [String] = [], keyHelpURL: URL? = nil) {
        self.id = id
        self.litellmPrefix = litellmPrefix
        self.displayName = displayName
        self.systemImage = systemImage
        self.knownModels = knownModels
        self.defaultAPIBase = defaultAPIBase
        self.requiresAPIKey = requiresAPIKey
        self.keyPrefixes = keyPrefixes
        self.keyHelpURL = keyHelpURL
    }
}

public enum ProviderPresets {
    public static let custom = ProviderPreset(
        id: "custom",
        litellmPrefix: "",
        displayName: "Personnalisé",
        systemImage: "slider.horizontal.3",
        knownModels: []
    )

    public static let all: [ProviderPreset] = [
        ProviderPreset(
            id: "openai",
            litellmPrefix: "openai/",
            displayName: "OpenAI",
            systemImage: "circle.hexagongrid.fill",
            knownModels: [
                KnownModel(id: "gpt-4o"),
                KnownModel(id: "gpt-4o-mini"),
                KnownModel(id: "gpt-4.1"),
                KnownModel(id: "gpt-4.1-mini"),
                KnownModel(id: "gpt-4.1-nano"),
                KnownModel(id: "o3"),
                KnownModel(id: "o4-mini"),
            ],
            keyPrefixes: ["sk-proj-", "sk-svcacct-", "sk-"],
            keyHelpURL: URL(string: "https://platform.openai.com/api-keys")
        ),
        ProviderPreset(
            id: "anthropic",
            litellmPrefix: "anthropic/",
            displayName: "Anthropic",
            systemImage: "sparkles",
            knownModels: [
                KnownModel(id: "claude-opus-4-1"),
                KnownModel(id: "claude-sonnet-4-5"),
                KnownModel(id: "claude-haiku-4-5"),
            ],
            keyPrefixes: ["sk-ant-"],
            keyHelpURL: URL(string: "https://console.anthropic.com/settings/keys")
        ),
        ProviderPreset(
            id: "gemini",
            litellmPrefix: "gemini/",
            displayName: "Google Gemini",
            systemImage: "globe",
            knownModels: [
                KnownModel(id: "gemini-2.5-pro"),
                KnownModel(id: "gemini-2.5-flash"),
                KnownModel(id: "gemini-2.5-flash-lite"),
            ],
            keyPrefixes: ["AIza"],
            keyHelpURL: URL(string: "https://aistudio.google.com/apikey")
        ),
        ProviderPreset(
            id: "mistral",
            litellmPrefix: "mistral/",
            displayName: "Mistral",
            systemImage: "wind",
            knownModels: [
                KnownModel(id: "mistral-large-latest"),
                KnownModel(id: "mistral-medium-latest"),
                KnownModel(id: "mistral-small-latest"),
            ],
            keyHelpURL: URL(string: "https://console.mistral.ai/api-keys/")
        ),
        ProviderPreset(
            id: "ollama",
            litellmPrefix: "ollama/",
            displayName: "Ollama (local)",
            systemImage: "desktopcomputer",
            knownModels: [
                KnownModel(id: "llama3.3"),
                KnownModel(id: "qwen3"),
                KnownModel(id: "mistral"),
                KnownModel(id: "deepseek-r1"),
            ],
            defaultAPIBase: "http://127.0.0.1:11434",
            requiresAPIKey: false
        ),
        ProviderPreset(
            id: "azure",
            litellmPrefix: "azure/",
            displayName: "Azure OpenAI",
            systemImage: "cloud.fill",
            knownModels: [],
            keyHelpURL: URL(string: "https://portal.azure.com/")
        ),
        custom,
    ]

    public static func preset(id: String) -> ProviderPreset {
        all.first { $0.id == id } ?? custom
    }

    /// Détecte le fournisseur à partir d'une clé API collée (préfixe connu).
    /// Le preset dont le préfixe correspondant est le plus long gagne (« sk-ant- » > « sk- »).
    public static func detect(fromAPIKey key: String) -> ProviderPreset? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return nil }
        var best: (preset: ProviderPreset, matchLen: Int)? = nil
        for preset in all where preset.id != "custom" {
            if let len = preset.keyPrefixes.filter({ k.hasPrefix($0) }).map(\.count).max(),
               best == nil || len > best!.matchLen {
                best = (preset, len)
            }
        }
        return best?.preset
    }

    /// Retrouve le preset correspondant à un `litellm_params.model` (« openai/gpt-4o » → openai).
    public static func preset(forProviderModel providerModel: String) -> ProviderPreset {
        for preset in all where !preset.litellmPrefix.isEmpty {
            if providerModel.hasPrefix(preset.litellmPrefix) {
                return preset
            }
        }
        return custom
    }

    /// Construit le `litellm_params.model` complet pour un preset + un id de modèle.
    public static func fullModel(preset: ProviderPreset, modelID: String) -> String {
        preset.litellmPrefix + modelID
    }

    /// Extrait l'id du modèle nu depuis un `litellm_params.model` (« openai/gpt-4o » → « gpt-4o »).
    public static func bareModelID(from providerModel: String) -> String {
        if let slash = providerModel.firstIndex(of: "/") {
            return String(providerModel[providerModel.index(after: slash)...])
        }
        return providerModel
    }
}

// MARK: - Catalogue Ollama local

/// Liste les modèles installés sur une instance Ollama (`GET {apiBase}/api/tags`).
public enum OllamaCatalog {
    public struct TagsResponse: Decodable, Sendable {
        public let models: [TagModel]?
        public struct TagModel: Decodable, Sendable {
            public let name: String
        }
    }

    public static func fetchModels(apiBase: String) async throws -> [String] {
        var base = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/api/tags") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return (decoded.models ?? []).map(\.name).sorted()
    }
}
