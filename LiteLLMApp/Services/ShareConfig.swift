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
    case codex, claudeCode, openAICompatible, anthropicCompatible

    public var id: String { rawValue }

    /// Commande à vérifier/installer pour les outils en ligne de commande.
    public var executable: String? {
        switch self {
        case .codex: return "codex"
        case .claudeCode: return "claude"
        case .openAICompatible, .anthropicCompatible: return nil
        }
    }

    /// Commande d'installation suggérée si l'outil est absent.
    public var installCommand: String? {
        switch self {
        case .codex: return "npm install -g @openai/codex"
        case .claudeCode: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .openAICompatible, .anthropicCompatible: return nil
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
                + "env_key = \"LITELLM_API_KEY\", wire_api = \"responses\" }"
            return """
            LITELLM_API_KEY=\(key) codex \\
              -c model_provider=litellm \\
              -c \(shellQuote(provider)) \\
              -m \(quotedModel)
            """
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
        return """
        #!/bin/zsh
        cd ~
        if ! command -v \(executable) >/dev/null 2>&1; then
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
