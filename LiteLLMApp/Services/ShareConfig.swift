import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Génère et copie dans le presse-papiers la configuration de connexion au proxy,
/// prête à coller dans n'importe quel outil compatible OpenAI.
public enum ShareConfig {
    /// Texte copiable : base URL + clé + modèle + exemple curl.
    public static func snippet(baseURL: String, apiKey: String, model: String, l10n: L10n = .shared) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let v1 = base + "/v1"
        return """
        \(l10n.t("Base URL :")) \(v1)
        \(l10n.t("Clé API  :")) \(apiKey)
        \(l10n.t("Modèle   :")) \(model)

        \(l10n.t("# Exemple de requête (compatible OpenAI) :"))
        curl \(v1)/chat/completions \\
          -H "Authorization: Bearer \(apiKey)" \\
          -H "Content-Type: application/json" \\
          -d '{"model": "\(model)", "messages": [{"role": "user", "content": "Bonjour"}]}'
        """
    }

    /// Copie le snippet dans le presse-papiers. Renvoie le texte copié.
    @discardableResult
    public static func copyToPasteboard(baseURL: String, apiKey: String, model: String,
                                        l10n: L10n = .shared) -> String {
        let text = snippet(baseURL: baseURL, apiKey: apiKey, model: model, l10n: l10n)
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
        return text
    }

    public static func copyValue(_ value: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #endif
    }
}

// MARK: - Outils externes (Codex, Claude Code…)

/// Outil externe que l'on peut brancher sur le proxy local, quel que soit le fournisseur réel :
/// le proxy traduit les formats OpenAI (Chat Completions / Responses) et Anthropic (Messages).
public enum ExternalTool: String, CaseIterable, Identifiable, Sendable {
    case codex, codexApp, claudeCode, openAICompatible, anthropicCompatible

    public var id: String { rawValue }

    /// Commande à vérifier/installer pour les outils en ligne de commande.
    public var executable: String? {
        switch self {
        case .codex: return "codex"
        case .claudeCode: return "claude"
        case .codexApp, .openAICompatible, .anthropicCompatible: return nil
        }
    }

    /// Emplacements connus de l'outil quand il n'est pas dans le PATH (ex. CLI embarqué dans ChatGPT.app).
    public var fallbackPaths: [String] {
        switch self {
        case .codex: return ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
        default: return []
        }
    }

    /// Commande d'installation suggérée si l'outil est absent.
    public var installCommand: String? {
        switch self {
        case .codex: return "npm install -g @openai/codex"
        case .claudeCode: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codexApp, .openAICompatible, .anthropicCompatible: return nil
        }
    }
}

extension ShareConfig {
    /// Échappement shell POSIX (guillemets simples).
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func normalizedBase(_ baseURL: String) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    /// Commande prête à coller dans le Terminal pour utiliser `tool` via le proxy avec `model`.
    public static func command(for tool: ExternalTool, baseURL: String, apiKey: String, model: String) -> String {
        let base = normalizedBase(baseURL)
        let key = shellQuote(apiKey)
        let quotedModel = shellQuote(model)
        switch tool {
        case .codex:
            // Fournisseur « litellm » déclaré à la volée : la config de Codex n'est pas modifiée.
            let provider = "model_providers.litellm={ name = \"LiteLLM\", base_url = \"\(base)/v1\", "
                + "env_key = \"LITELLM_API_KEY\", wire_api = \"responses\", "
                + "http_headers = { \"\(YAMLEmitter.modelHeader)\" = \(YAMLEmitter.quote(model)) } }"
            return """
            LITELLM_API_KEY=\(key) codex \\
              -c model_provider=litellm \\
              -c \(shellQuote(provider)) \\
              -m \(quotedModel)
            """
        case .codexApp:
            return CodexAppConfig.providerBlock(baseURL: base, apiKey: apiKey, model: model)
        case .claudeCode:
            return """
            ANTHROPIC_BASE_URL=\(shellQuote(base)) \\
            ANTHROPIC_AUTH_TOKEN=\(key) \\
            ANTHROPIC_MODEL=\(quotedModel) \\
            ANTHROPIC_DEFAULT_HAIKU_MODEL=\(quotedModel) \\
            claude
            """
        case .openAICompatible:
            return """
            export OPENAI_BASE_URL=\(shellQuote(base + "/v1"))
            export OPENAI_API_KEY=\(key)
            # model: \(model)
            """
        case .anthropicCompatible:
            return """
            export ANTHROPIC_BASE_URL=\(shellQuote(base))
            export ANTHROPIC_API_KEY=\(key)
            # model: \(model)
            """
        }
    }

    /// Script `.command` qui vérifie la présence de l'outil puis le lance avec la bonne configuration.
    public static func launchScript(for tool: ExternalTool, baseURL: String, apiKey: String, model: String,
                                    l10n: L10n = .shared) -> String {
        let command = command(for: tool, baseURL: baseURL, apiKey: apiKey, model: model)
        guard let executable = tool.executable else { return "#!/bin/zsh\n" + command + "\n" }
        let install = tool.installCommand ?? ""
        // Repli sur une copie embarquée (fonction zsh : les affectations en préfixe restent exportées).
        let fallbacks = tool.fallbackPaths.map { path in
            "elif [ -x \(shellQuote(path)) ]; then\n  \(executable)() { \(shellQuote(path)) \"$@\"; }"
        }.joined(separator: "\n")
        return """
        #!/bin/zsh
        cd ~
        if command -v \(executable) >/dev/null 2>&1; then
          :
        \(fallbacks.isEmpty ? "" : fallbacks + "\n")else
          echo "\(l10n.t("« %@ » est introuvable. Installez-le avec :", executable))"
          echo "  \(install)"
          exit 1
        fi
        \(command)

        """
    }

    #if canImport(AppKit)
    /// Ouvre un Terminal qui lance `tool` branché sur le proxy (script 0700 dans Application Support).
    public static func launchInTerminal(_ tool: ExternalTool, baseURL: String, apiKey: String, model: String) throws {
        let url = ProxyPaths.appSupport().appendingPathComponent("launch-\(tool.rawValue).command")
        let script = launchScript(for: tool, baseURL: baseURL, apiKey: apiKey, model: model)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }
    #endif
}

// MARK: - App Codex (ChatGPT pour Mac)

/// Branche l'app Codex (et le CLI `codex`) sur le proxy en éditant `~/.codex/config.toml`.
/// Une app graphique ne voit pas les variables du Terminal : la clé est donc écrite dans la config.
/// Chaque modification est marquée pour pouvoir être annulée et restaurer les réglages d'origine.
public enum CodexAppConfig {
    static let providerID = "litellm-app"
    static let lineMarker = " # LiteLLM-App"
    static let disabledPrefix = "# LiteLLM-App: "
    static let blockStart = "# >>> LiteLLM-App (géré automatiquement)"
    static let blockEnd = "# <<< LiteLLM-App"
    /// Clés de premier niveau remplacées pendant l'activation (réactivées à la désactivation).
    static let overriddenKeys = ["model", "model_provider", "model_reasoning_effort", "model_catalog_json"]

    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
    }

    /// Catalogue de modèles (`model_catalog_json`) : le sélecteur de l'app Codex n'affiche que ceux du proxy.
    public static var catalogURL: URL {
        configURL.deletingLastPathComponent().appendingPathComponent("litellm-app-models.json")
    }

    /// Table `[model_providers.litellm-app]` pointant sur le proxy.
    /// L'en-tête de modèle redirige vers `model` les modèles OpenAI choisis dans le sélecteur de Codex.
    public static func providerBlock(baseURL: String, apiKey: String, model: String) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return """
        [model_providers.\(providerID)]
        name = "LiteLLM"
        base_url = \(YAMLEmitter.quote(base + "/v1"))
        experimental_bearer_token = \(YAMLEmitter.quote(apiKey))
        wire_api = "responses"
        http_headers = { "\(YAMLEmitter.modelHeader)" = \(YAMLEmitter.quote(model)) }
        """
    }

    public static func isEnabled(_ toml: String) -> Bool {
        toml.contains(blockStart)
    }

    /// Modèle actuellement imposé par LiteLLM-App, s'il est activé.
    public static func enabledModel(_ toml: String) -> String? {
        for line in toml.components(separatedBy: "\n") where line.hasSuffix(lineMarker) {
            let body = line.dropLast(lineMarker.count)
            guard key(of: String(body)) == "model", let eq = body.firstIndex(of: "=") else { continue }
            return body[body.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    /// Ajoute (ou remplace) la configuration LiteLLM-App.
    public static func enable(in toml: String, baseURL: String, apiKey: String, model: String,
                              catalogPath: String? = nil) -> String {
        var lines = disable(in: toml).components(separatedBy: "\n")
        while lines.last?.isEmpty == true { lines.removeLast() }
        // Les clés de premier niveau doivent précéder la première table `[...]`.
        let firstTable = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        for i in 0..<firstTable where overriddenKeys.contains(key(of: lines[i]) ?? "") {
            lines[i] = disabledPrefix + lines[i]
        }
        let header = [
            "model = \(YAMLEmitter.quote(model))" + lineMarker,
            "model_provider = \"\(providerID)\"" + lineMarker,
        ] + (catalogPath.map { ["model_catalog_json = \(YAMLEmitter.quote($0))" + lineMarker] } ?? [])
        lines.insert(contentsOf: header, at: 0)
        lines += ["", blockStart, providerBlock(baseURL: baseURL, apiKey: apiKey, model: model), blockEnd]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Retire la configuration LiteLLM-App et réactive les réglages d'origine.
    public static func disable(in toml: String) -> String {
        let lines = toml.components(separatedBy: "\n")
        // Clés redéfinies entre-temps (ex. modèle changé dans l'app Codex) : on ne restaure pas
        // l'ancienne valeur, sinon la clé serait en double et le TOML invalide.
        let firstTable = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        let activeKeys = Set(lines[..<firstTable].filter { !$0.hasSuffix(lineMarker) }.compactMap(key(of:)))
        var result: [String] = []
        var inBlock = false
        for line in lines {
            if line == blockStart { inBlock = true; continue }
            if inBlock { if line == blockEnd { inBlock = false }; continue }
            if line.hasSuffix(lineMarker) { continue }
            if line.hasPrefix(disabledPrefix) {
                let original = String(line.dropFirst(disabledPrefix.count))
                if !activeKeys.contains(key(of: original) ?? "") { result.append(original) }
                continue
            }
            result.append(line)
        }
        // Retire la ligne vide laissée avant le bloc.
        while result.count > 1, result[result.count - 1].isEmpty, result[result.count - 2].isEmpty {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }

    /// Nom de la clé d'une ligne `clé = valeur` (nil pour un commentaire, une table, une ligne vide).
    static func key(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("["), let eq = trimmed.firstIndex(of: "=") else { return nil }
        return trimmed[..<eq].trimmingCharacters(in: .whitespaces)
    }

    // MARK: Catalogue de modèles

    /// Emplacements possibles du CLI Codex (une app graphique n'a pas le PATH du Terminal).
    static var executableCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ExternalTool.codex.fallbackPaths + [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex",
        ]
    }

    /// Entrée du catalogue de Codex servant de modèle : la première en mode outils classique
    /// (appels de fonctions), que les autres fournisseurs savent exécuter via LiteLLM.
    /// Les modèles « code mode » de Codex n'envoient pas d'outils et ne conviennent pas.
    public static func fetchTemplate() async -> [String: Any]? {
        await Task.detached {
            guard let path = executableCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
                return nil
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["debug", "models", "--bundled"]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return template(fromCatalog: data)
        }.value
    }

    static func template(fromCatalog data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return nil }
        return models.first { $0["tool_mode"] == nil || $0["tool_mode"] is NSNull }
    }

    /// Catalogue listant les modèles du proxy (`defaultModel` en premier).
    /// `contextLimit` : fenêtre de contexte annoncée à Codex (il compacte en l'approchant), ramenée
    /// au maximum réel de chaque modèle quand il est connu (`contextWindows`, voir `fetchContextWindows`).
    public static func catalog(models: [ProxyModel], defaultModel: String, template: [String: Any]?,
                               contextLimit: Int = defaultContextLimit,
                               contextWindows: [String: Int] = [:]) throws -> Data {
        let ordered = models.filter { $0.name == defaultModel } + models.filter { $0.name != defaultModel }
        let entries: [[String: Any]] = ordered.enumerated().map { index, model in
            let slug = model.name
            var entry = template ?? [
                "base_instructions": "You are a coding agent running in the user's terminal. Use the available tools to inspect and edit files and run commands until the task is complete, then summarize what you did.",
                "shell_type": "unified_exec",
                "support_verbosity": false,
                "truncation_policy": ["mode": "tokens", "limit": 10000],
            ]
            entry["slug"] = slug
            entry["display_name"] = slug
            entry["description"] = catalogDescription(contextLimit: contextLimit)
            let window = min(contextWindows[slug] ?? contextLimit, contextLimit)
            entry["context_window"] = window
            entry["max_context_window"] = window
            entry["visibility"] = "list"
            entry["supported_in_api"] = true
            entry["priority"] = index
            // Niveaux de raisonnement traduits par le hook du proxy (voir `YAMLEmitter.renderHooks`).
            entry["supported_reasoning_levels"] = model.reasoningEfforts.map { ["effort": $0, "description": $0] }
            entry["default_reasoning_level"] = "medium"
            entry["supports_reasoning_effort_updates"] = true
            // Réglages propres aux modèles OpenAI (vitesse, sous-agents…) désactivés.
            entry["experimental_supported_tools"] = [Any]()
            entry["additional_speed_tiers"] = [Any]()
            entry["service_tiers"] = [Any]()
            entry["supports_search_tool"] = false
            entry["use_responses_lite"] = false
            for key in ["tool_mode", "apply_patch_tool_type", "upgrade",
                        "availability_nux", "multi_agent_version", "multi_agent_reasoning_effort",
                        "available_access_programs"] {
                entry.removeValue(forKey: key)
            }
            return entry
        }
        return try JSONSerialization.data(withJSONObject: ["models": entries], options: [.sortedKeys])
    }

    /// Tailles de contexte proposées dans l'app ; 272k est la valeur de Codex pour ses propres modèles.
    public static let contextLimits = [128_000, 272_000, 500_000, 1_000_000]
    public static let defaultContextLimit = 272_000

    /// Description affichée dans le sélecteur de Codex. Elle sert aussi à repérer un catalogue
    /// généré avec d'autres réglages (« Mettre à jour » dans l'app).
    static func catalogDescription(contextLimit: Int) -> String {
        "LiteLLM-App · \(formatTokens(contextLimit)) max"
    }

    /// « 272k », « 1M »…
    public static func formatTokens(_ count: Int) -> String {
        count >= 1_000_000 && count % 1_000_000 == 0 ? "\(count / 1_000_000)M" : "\(count / 1000)k"
    }

    /// Modèles listés dans le catalogue installé, s'il a été généré avec ces réglages (vide sinon).
    public static func catalogModels(contextLimit: Int) -> [String] {
        guard let data = try? Data(contentsOf: catalogURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]],
              models.allSatisfy({ $0["description"] as? String == catalogDescription(contextLimit: contextLimit) })
        else { return [] }
        return models.compactMap { $0["slug"] as? String }
    }

    /// Taille de contexte réelle de chaque modèle selon le proxy (`/model/info`, `max_input_tokens`).
    /// Vide si le proxy ne répond pas ; les modèles inconnus de LiteLLM sont absents.
    public static func fetchContextWindows(baseURL: String, apiKey: String) async -> [String: Int] {
        var base = baseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/model/info") else { return [:] }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [:] }
        return contextWindows(fromModelInfo: data)
    }

    static func contextWindows(fromModelInfo data: Data) -> [String: Int] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return [:] }
        var windows: [String: Int] = [:]
        for entry in entries {
            guard let name = entry["model_name"] as? String,
                  let tokens = (entry["model_info"] as? [String: Any])?["max_input_tokens"] as? Int,
                  tokens > 0 else { continue }
            // Plusieurs déploiements pour un même nom : on garde le plus petit.
            windows[name] = min(windows[name] ?? tokens, tokens)
        }
        return windows
    }

    // MARK: Fichier

    public static func read() -> String {
        (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
    }

    /// Écrit la nouvelle config ; sauvegarde l'originale une seule fois (`config.toml.bak-litellm-app`).
    public static func write(_ toml: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = configURL.appendingPathExtension("bak-litellm-app")
        if fm.fileExists(atPath: configURL.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: configURL, to: backup)
        }
        try toml.write(to: configURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }
}
