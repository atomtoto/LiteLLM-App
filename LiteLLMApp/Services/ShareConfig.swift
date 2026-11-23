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
