import Foundation

// MARK: - Modèle de configuration du proxy local

/// Un modèle déclaré dans le `config.yaml` du proxy LiteLLM.
public struct ProxyModel: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Nom exposé par le proxy (`model_name`), ex. « gpt-4o ».
    public var name: String
    /// Modèle LiteLLM complet (`litellm_params.model`), ex. « openai/gpt-4o », « ollama/llama3 ».
    public var providerModel: String
    public var apiKey: String
    /// Base URL optionnelle (ex. Ollama local, vLLM…).
    public var apiBase: String

    public init(id: UUID = UUID(), name: String = "", providerModel: String = "", apiKey: String = "", apiBase: String = "") {
        self.id = id
        self.name = name
        self.providerModel = providerModel
        self.apiKey = apiKey
        self.apiBase = apiBase
    }
}

/// Réglages du proxy local persistés en JSON dans Application Support.
public struct ProxySettingsData: Codable, Equatable, Sendable {
    public var host: String = "127.0.0.1"
    public var port: Int = 4000
    public var stopOnQuit: Bool = true
    public var autoStart: Bool = false
    public var models: [ProxyModel] = []

    public init(host: String = "127.0.0.1", port: Int = 4000, stopOnQuit: Bool = true,
                autoStart: Bool = false, models: [ProxyModel] = []) {
        self.host = host
        self.port = port
        self.stopOnQuit = stopOnQuit
        self.autoStart = autoStart
        self.models = models
    }
}

// MARK: - Chemins (Application Support)

public enum ProxyPaths {
    /// Dossier Application Support de l'app (créé si besoin).
    public static func appSupport(create: Bool = true) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("LiteLLM-App", isDirectory: true)
        if create { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    public static var venv: URL { appSupport().appendingPathComponent("venv", isDirectory: true) }
    public static var litellmBinary: URL { venv.appendingPathComponent("bin/litellm") }
    public static var pipBinary: URL { venv.appendingPathComponent("bin/pip") }
    public static var configFile: URL { appSupport().appendingPathComponent("config.yaml") }
    public static var settingsFile: URL { appSupport().appendingPathComponent("proxy-settings.json") }
}

// MARK: - Émission YAML (sans dépendance externe)

public enum YAMLEmitter {
    /// Double-quote systématique (valide YAML, échappe `\` et `"`).
    public static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Rend un `config.yaml` LiteLLM complet.
    public static func renderConfig(settings: ProxySettingsData, masterKey: String) -> String {
        var lines: [String] = [
            "# Généré automatiquement par LiteLLM-App — toute édition manuelle sera écrasée.",
        ]
        let validModels = settings.models.filter { !$0.name.isEmpty && !$0.providerModel.isEmpty }
        if validModels.isEmpty {
            lines.append("model_list: []")
        } else {
            lines.append("model_list:")
            for model in validModels {
                lines.append("  - model_name: \(quote(model.name))")
                lines.append("    litellm_params:")
                lines.append("      model: \(quote(model.providerModel))")
                if !model.apiKey.isEmpty {
                    lines.append("      api_key: \(quote(model.apiKey))")
                }
                if !model.apiBase.isEmpty {
                    lines.append("      api_base: \(quote(model.apiBase))")
                }
            }
        }
        lines.append("general_settings:")
        if !masterKey.isEmpty {
            lines.append("  master_key: \(quote(masterKey))")
        }
        lines.append("litellm_settings:")
        lines.append("  drop_params: true")
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Persistance des réglages du proxy

public enum ProxySettingsStore {
    public static func load(from url: URL = ProxyPaths.settingsFile) -> ProxySettingsData {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ProxySettingsData.self, from: data) else {
            return ProxySettingsData()
        }
        return decoded
    }

    public static func save(_ settings: ProxySettingsData, to url: URL = ProxyPaths.settingsFile) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Écriture du config.yaml (permissions 0600 car il contient des clés)

public enum ProxyConfigWriter {
    @discardableResult
    public static func write(settings: ProxySettingsData, masterKey: String,
                             to url: URL = ProxyPaths.configFile) throws -> String {
        let yaml = YAMLEmitter.renderConfig(settings: settings, masterKey: masterKey)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return yaml
    }
}
