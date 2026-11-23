import Foundation

/// Client asynchrone pour l'API compatible OpenAI d'un proxy LiteLLM.
public actor LiteLLMClient {
    public let baseURL: URL
    private let apiKey: String?
    private let session: URLSession

    public init(baseURL: URL, apiKey: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - Requêtes

    private func makeRequest(path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// `GET /health` — renvoie true si le proxy répond en 2xx.
    public func health() async throws -> Bool {
        let (_, response) = try await session.data(for: makeRequest(path: "health"))
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// `GET /v1/models` — liste les modèles exposés par le proxy.
    public func listModels() async throws -> [ModelInfo] {
        let (data, response) = try await session.data(for: makeRequest(path: "v1/models"))
        try Self.ensureSuccess(response, data: data)
        let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return decoded.data
    }

    /// `POST /v1/chat/completions` sans streaming.
    public func chatCompletion(request body: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        var request = makeRequest(path: "v1/chat/completions", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response, data: data)
        do {
            return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw LiteLLMError.decodingFailed(error.localizedDescription)
        }
    }

    /// `POST /v1/chat/completions` minimal non streamé, pour valider qu'un modèle répond.
    /// - Returns: le contenu de la réponse (attendu : « OK »).
    public func testChatCompletion(model: String) async throws -> String {
        let body = ChatCompletionRequest(
            model: model,
            messages: [ChatMessageDTO(role: "user", content: "Reply with exactly: OK")],
            maxTokens: 16,
            stream: false
        )
        let response = try await chatCompletion(request: body)
        return response.choices.first?.message?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// `POST /v1/chat/completions` en streaming (SSE).
    /// - Parameter onDelta: appelé pour chaque chunk reçu (peut être annulé via la tâche appelante).
    /// - Returns: l'usage total des tokens si le serveur l'a inclus (`stream_options.include_usage`).
    @discardableResult
    public func streamChatCompletion(
        request body: ChatCompletionRequest,
        onDelta: @Sendable (ChatCompletionChunk) async -> Void
    ) async throws -> Usage? {
        var streamingBody = body
        streamingBody.stream = true
        streamingBody.streamOptions = StreamOptions(includeUsage: true)

        var request = makeRequest(path: "v1/chat/completions", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(streamingBody)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LiteLLMError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.httpError(status: http.statusCode, data: data)
        }

        var parser = SSEParser()
        var usage: Usage?
        var done = false

        func handle(_ payload: String) async {
            if payload == "[DONE]" {
                done = true
                return
            }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) else { return }
            if let chunkUsage = chunk.usage { usage = chunkUsage }
            await onDelta(chunk)
        }

        for try await line in bytes.lines {
            for payload in parser.feed(String(line) + "\n") {
                await handle(payload)
                if done { return usage }
            }
        }
        for payload in parser.finish() {
            await handle(payload)
            if done { break }
        }
        return usage
    }

    // MARK: - Erreurs HTTP

    private static func ensureSuccess(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LiteLLMError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw httpError(status: http.statusCode, data: data ?? Data())
        }
    }

    private static func httpError(status: Int, data: Data) -> LiteLLMError {
        let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error?.message
        let fallback = HTTPURLResponse.localizedString(forStatusCode: status)
        return .httpError(status: status, message: (message?.isEmpty == false ? message : nil) ?? fallback)
    }
}
