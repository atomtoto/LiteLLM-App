import Foundation

// MARK: - Modèles

/// Réponse de `GET /v1/models`.
public struct ModelListResponse: Decodable, Sendable {
    public let data: [ModelInfo]
    public let object: String?
}

public struct ModelInfo: Decodable, Identifiable, Sendable {
    public let id: String
    public let object: String?
    public let created: Int?
    public let ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}

// MARK: - Chat completions

public struct ChatMessageDTO: Codable, Sendable, Equatable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct StreamOptions: Encodable, Sendable {
    public let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }

    public init(includeUsage: Bool) {
        self.includeUsage = includeUsage
    }
}

public struct ChatCompletionRequest: Encodable, Sendable {
    public let model: String
    public let messages: [ChatMessageDTO]
    public var temperature: Double?
    public var maxTokens: Int?
    public var topP: Double?
    public var stream: Bool
    public var streamOptions: StreamOptions?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case stream
        case streamOptions = "stream_options"
    }

    public init(model: String, messages: [ChatMessageDTO], temperature: Double? = nil,
                maxTokens: Int? = nil, topP: Double? = nil, stream: Bool = false,
                streamOptions: StreamOptions? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.stream = stream
        self.streamOptions = streamOptions
    }
}

public struct Usage: Decodable, Sendable, Equatable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

/// Réponse non streamée de `POST /v1/chat/completions`.
public struct ChatCompletionResponse: Decodable, Sendable {
    public let id: String?
    public let model: String?
    public let choices: [Choice]
    public let usage: Usage?

    public struct Choice: Decodable, Sendable {
        public let index: Int?
        public let message: ChatMessageDTO?
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }
}

/// Un chunk SSE de `POST /v1/chat/completions` avec `stream: true`.
public struct ChatCompletionChunk: Decodable, Sendable {
    public let id: String?
    public let model: String?
    public let choices: [StreamChoice]
    public let usage: Usage?

    public struct StreamChoice: Decodable, Sendable {
        public let index: Int?
        public let delta: Delta
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    public struct Delta: Decodable, Sendable {
        public let role: String?
        public let content: String?
        public let reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case role, content
            case reasoningContent = "reasoning_content"
        }
    }
}

// MARK: - Erreurs

public struct APIErrorResponse: Decodable, Sendable {
    public let error: APIError?

    public struct APIError: Decodable, Sendable {
        public let message: String?
        public let type: String?
        public let code: String?
    }
}

public enum LiteLLMError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(status: Int, message: String)
    case decodingFailed(String)

    public var errorDescription: String? {
        let l10n = L10n.shared
        switch self {
        case .invalidURL:
            return l10n.t("URL du serveur invalide.")
        case .invalidResponse:
            return l10n.t("Réponse invalide du serveur.")
        case .httpError(let status, let message):
            return l10n.t("Erreur HTTP %@ : %@", status, message)
        case .decodingFailed(let detail):
            return l10n.t("Réponse illisible : %@", detail)
        }
    }
}

/// Traduit une erreur technique en message compréhensible par un utilisateur non
/// technique (cause probable + quoi faire), en gardant le détail technique à la fin.
public enum FriendlyError {
    public static func message(for error: Error, l10n: L10n = .shared) -> String {
        if let error = error as? LiteLLMError, case .httpError(let status, let detail) = error {
            let hint: String
            switch status {
            case 401, 403:
                hint = l10n.t("La clé API a été refusée. Vérifiez la clé de votre fournisseur dans « Fournisseurs d'IA », ou relancez l'assistant de configuration.")
            case 404:
                hint = l10n.t("Ce modèle est introuvable. Choisissez un autre modèle dans la liste.")
            case 408, 504:
                hint = l10n.t("Le fournisseur a mis trop de temps à répondre. Réessayez dans un instant.")
            case 429:
                hint = l10n.t("Limite atteinte chez le fournisseur (trop de requêtes ou crédit épuisé). Patientez un peu ou vérifiez votre compte chez le fournisseur.")
            case 400:
                hint = l10n.t("La requête a été refusée par le fournisseur. Vérifiez que le modèle choisi est correct.")
            case 500...599:
                hint = l10n.t("Le fournisseur ou le proxy a rencontré une erreur. Réessayez dans un instant.")
            default:
                hint = l10n.t("Le serveur a renvoyé une erreur.")
            }
            return hint + "\n\n" + l10n.t("Détail : %@", "HTTP \(status) — \(detail)")
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed:
                return l10n.t("Impossible de joindre le serveur. Vérifiez que le proxy est démarré (bouton « Démarrer » en haut de la fenêtre).")
            case .notConnectedToInternet:
                return l10n.t("Pas de connexion Internet.")
            case .timedOut:
                return l10n.t("Le serveur ne répond pas (délai dépassé). Réessayez dans un instant.")
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
