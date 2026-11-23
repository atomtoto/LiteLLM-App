import Foundation

/// Parser incrémental pour les événements Server-Sent Events (SSE) émis par
/// les endpoints de streaming de LiteLLM (`data: {...}` puis `data: [DONE]`).
public struct SSEParser: Sendable {
    private var buffer = ""

    public init() {}

    /// Ajoute un morceau de texte brut et renvoie les payloads `data:` complets, dans l'ordre.
    public mutating func feed(_ chunk: String) -> [String] {
        // Normalise CRLF / CR en LF ("\r\n" forme un seul grapheme en Swift).
        buffer += chunk
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var payloads: [String] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = buffer[..<newline]
            buffer.removeSubrange(..<buffer.index(after: newline))
            if let payload = Self.dataPayload(of: line) {
                payloads.append(payload)
            }
        }
        return payloads
    }

    /// Renvoie un éventuel payload final non terminé par un saut de ligne.
    public mutating func finish() -> [String] {
        defer { buffer = "" }
        guard !buffer.isEmpty, let payload = Self.dataPayload(of: Substring(buffer)) else { return [] }
        return [payload]
    }

    /// Extrait le payload d'une ligne SSE de la forme `data: <payload>` (ignore commentaires, `id:`, `event:`…).
    static func dataPayload<S: StringProtocol>(of line: S) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        return payload.isEmpty ? nil : payload
    }
}
