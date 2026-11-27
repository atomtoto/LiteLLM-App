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

extension ProxyModel {
    /// Claude ≥ 4.6 via l'API Anthropic : la réflexion est « adaptive » et son niveau passe par
    /// `output_config.effort` (l'ancien `thinking.budget_tokens` est refusé par les modèles récents).
    public var usesAdaptiveThinking: Bool {
        let id = providerModel.lowercased()
        guard id.hasPrefix("anthropic/"),
              let match = id.firstMatch(of: /claude-(?:opus|sonnet|haiku)-(\d+)(?:-(\d{1,2})(?!\d))?/) else {
            return false
        }
        let major = Int(match.1) ?? 0
        let minor = match.2.flatMap { Int($0) } ?? 0
        return major > 4 || (major == 4 && minor >= 6)
    }

    /// Niveaux de raisonnement proposés dans Codex pour ce modèle (traduits par le hook du proxy).
    public var reasoningEfforts: [String] {
        usesAdaptiveThinking ? ["low", "medium", "high", "xhigh"] : ["low", "medium", "high"]
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
        lines.append("  callbacks: \(hooksModule).proxy_handler_instance")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Module Python des hooks, résolu par LiteLLM dans le dossier du config.yaml.
    public static let hooksModule = "litellm_app_hooks"
    /// En-tête HTTP indiquant au hook le modèle de repli (voir `CodexAppConfig`).
    public static let modelHeader = "x-litellm-app-model"

    /// Hook appliqué avant chaque requête : redirige les modèles inconnus vers le modèle choisi
    /// pour Codex, retire ce que seuls les modèles OpenAI comprennent (outils `namespace`,
    /// `client_metadata`, champ `safeguards`) et traduit le niveau de raisonnement, sans quoi
    /// Anthropic, Mistral… renvoient une erreur.
    public static func renderHooks(settings: ProxySettingsData) -> String {
        let valid = settings.models.filter { !$0.name.isEmpty && !$0.providerModel.isEmpty }
        func pySet(_ models: [ProxyModel]) -> String {
            models.isEmpty ? "set()" : "{" + models.map { quote($0.name) }.sorted().joined(separator: ", ") + "}"
        }
        let native = valid.filter { $0.providerModel.lowercased().hasPrefix("openai/") }
        let adaptive = valid.filter(\.usesAdaptiveThinking)
        return """
        # Généré automatiquement par LiteLLM-App — toute édition manuelle sera écrasée.
        from litellm.integrations.custom_logger import CustomLogger

        KNOWN_MODELS = \(pySet(valid))
        # Modèles OpenAI : la requête leur est transmise telle quelle.
        NATIVE_MODELS = \(pySet(native))
        # En-tête envoyé par Codex : modèle à utiliser quand il demande un modèle inconnu du proxy
        # (ex. « gpt-6.2-sol » choisi dans le sélecteur de l'app Codex).
        MODEL_HEADER = "\(modelHeader)"
        # Claude ≥ 4.6 : réflexion « adaptive » + output_config.effort (« max » est refusé par LiteLLM).
        # Outils propres à OpenAI : sous-agents (`namespace`) et recherche web, que LiteLLM change en
        # recherche exécutée par le fournisseur, dont Codex ne sait pas renvoyer le résultat.
        UNSUPPORTED_TOOLS = {"namespace", "web_search", "web_search_preview"}
        ADAPTIVE_MODELS = \(pySet(adaptive))
        ADAPTIVE_EFFORTS = {"minimal": "low", "low": "low", "medium": "medium", "high": "high",
                            "xhigh": "xhigh", "max": "xhigh", "ultra": "xhigh"}
        # Autres fournisseurs : niveaux standard (« minimal » donnerait un budget de réflexion trop petit).
        STANDARD_EFFORTS = {"none": "none", "minimal": "low", "low": "low", "medium": "medium", "high": "high"}


        def is_server_tool_item(item):
            if not isinstance(item, dict):
                return False
            ids = (item.get("call_id"), item.get("id"))
            return any(isinstance(i, str) and i.startswith("srvtoolu_") for i in ids)


        class LiteLLMAppHooks(CustomLogger):
            async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
                headers = (data.get("proxy_server_request") or {}).get("headers") or {}
                fallback = next((v for k, v in headers.items() if k.lower() == MODEL_HEADER), None)
                if data.get("model") not in KNOWN_MODELS and fallback in KNOWN_MODELS:
                    data["model"] = fallback
                if data.get("model") in NATIVE_MODELS:
                    return data
                tools = data.get("tools")
                if isinstance(tools, list):
                    data["tools"] = [t for t in tools if not (isinstance(t, dict) and t.get("type") in UNSUPPORTED_TOOLS)]
                # Recherches web déjà exécutées côté fournisseur (ids « srvtoolu_ ») : Codex les renvoie
                # comme ses propres appels d'outils, ce qu'Anthropic refuse. On les retire de l'historique.
                items = data.get("input")
                if isinstance(items, list):
                    data["input"] = [i for i in items if not is_server_tool_item(i)]
                data.pop("client_metadata", None)
                # « safeguards » envoyé par Codex (classifieur dangerous_tool_use) : les fournisseurs
                # autres qu'OpenAI le rejettent (422 extra_forbidden).
                data.pop("safeguards", None)
                reasoning = data.get("reasoning")
                effort = reasoning.get("effort") if isinstance(reasoning, dict) else None
                if effort is None:
                    return data
                if data.get("model") in ADAPTIVE_MODELS:
                    reasoning.pop("effort")
                    if effort != "none":
                        data["thinking"] = {"type": "adaptive"}
                        data["output_config"] = {"effort": ADAPTIVE_EFFORTS.get(effort, "high")}
                else:
                    reasoning["effort"] = STANDARD_EFFORTS.get(effort, "high")
                return data


        proxy_handler_instance = LiteLLMAppHooks()

        """
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
        let hooks = url.deletingLastPathComponent().appendingPathComponent("\(YAMLEmitter.hooksModule).py")
        try YAMLEmitter.renderHooks(settings: settings).write(to: hooks, atomically: true, encoding: .utf8)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return yaml
    }
}
