import XCTest
import Foundation

final class APIModelsTests: XCTestCase {
    func testDecodeModelList() throws {
        let json = """
        {"object":"list","data":[
          {"id":"gpt-4o","object":"model","created":1715367049,"owned_by":"openai"},
          {"id":"claude-sonnet","object":"model","created":0,"owned_by":"anthropic"}
        ]}
        """
        let response = try JSONDecoder().decode(ModelListResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.data.count, 2)
        XCTAssertEqual(response.data[0].id, "gpt-4o")
        XCTAssertEqual(response.data[0].ownedBy, "openai")
        XCTAssertEqual(response.data[1].id, "claude-sonnet")
    }

    func testDecodeCompletionChunkWithReasoning() throws {
        let json = """
        {"id":"chatcmpl-1","object":"chat.completion.chunk","model":"gpt-4o",
         "choices":[{"index":0,"delta":{"role":"assistant","reasoning_content":"réflexion…","content":"Bonjour"},"finish_reason":null}],
         "usage":null}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8))
        XCTAssertEqual(chunk.choices.count, 1)
        XCTAssertEqual(chunk.choices[0].delta.content, "Bonjour")
        XCTAssertEqual(chunk.choices[0].delta.reasoningContent, "réflexion…")
    }

    func testDecodeFinalUsageChunk() throws {
        let json = """
        {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[],
         "usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8))
        XCTAssertEqual(chunk.usage?.promptTokens, 10)
        XCTAssertEqual(chunk.usage?.totalTokens, 15)
    }

    func testDecodeChatCompletionResponse() throws {
        let json = """
        {"id":"chatcmpl-123","object":"chat.completion","created":1,"model":"gpt-4o",
         "choices":[{"index":0,"message":{"role":"assistant","content":"Bonjour !"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":8,"completion_tokens":3,"total_tokens":11}}
        """
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.choices[0].message?.content, "Bonjour !")
        XCTAssertEqual(response.choices[0].finishReason, "stop")
        XCTAssertEqual(response.usage?.totalTokens, 11)
    }

    func testEncodeChatCompletionRequestUsesSnakeCase() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [ChatMessageDTO(role: "user", content: "Salut")],
            temperature: 0.7,
            maxTokens: 512,
            topP: 0.9,
            stream: true,
            streamOptions: StreamOptions(includeUsage: true)
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "gpt-4o")
        XCTAssertEqual(object["max_tokens"] as? Int, 512)
        XCTAssertEqual(object["top_p"] as? Double, 0.9)
        XCTAssertEqual(object["stream"] as? Bool, true)
        let streamOptions = try XCTUnwrap(object["stream_options"] as? [String: Any])
        XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "Salut")
    }

    func testDecodeAPIError() throws {
        let json = #"{"error":{"message":"Invalid API key","type":"authentication_error","code":"401"}}"#
        let response = try JSONDecoder().decode(APIErrorResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.error?.message, "Invalid API key")
        XCTAssertEqual(response.error?.type, "authentication_error")
    }

    func testErrorDescription() {
        L10n.shared.lang = .fr
        let error = LiteLLMError.httpError(status: 401, message: "clé invalide")
        XCTAssertEqual(error.errorDescription, "Erreur HTTP 401 : clé invalide")
    }

    func testFriendlyErrorExplainsInvalidKey() {
        let l10n = L10n()
        l10n.lang = .fr
        let message = FriendlyError.message(for: LiteLLMError.httpError(status: 401, message: "bad key"), l10n: l10n)
        XCTAssertTrue(message.contains("clé API a été refusée"))
        XCTAssertTrue(message.contains("bad key"))
    }

    func testFriendlyErrorExplainsUnreachableServer() {
        let l10n = L10n()
        l10n.lang = .en
        let message = FriendlyError.message(for: URLError(.cannotConnectToHost), l10n: l10n)
        XCTAssertTrue(message.contains("Could not reach the server"))
    }

    func testRetryDropsTemperatureRejectedByModel() {
        let request = ChatCompletionRequest(model: "claude-opus-5-5", messages: [],
                                            temperature: 0.7, maxTokens: 1024, stream: true)
        let error = LiteLLMError.httpError(status: 400, message: "AnthropicException - `temperature` is deprecated for this model.")
        let retry = request.removingParametersRejected(by: error)
        XCTAssertNotNil(retry)
        XCTAssertNil(retry?.temperature)
        XCTAssertEqual(retry?.maxTokens, 1024)
    }

    func testNoRetryForUnrelatedErrors() {
        let request = ChatCompletionRequest(model: "m", messages: [], temperature: 0.7)
        XCTAssertNil(request.removingParametersRejected(by: LiteLLMError.httpError(status: 401, message: "temperature invalid")))
        XCTAssertNil(request.removingParametersRejected(by: LiteLLMError.httpError(status: 400, message: "Invalid model name")))
        // Rien à retirer : la requête n'a pas de température.
        let bare = ChatCompletionRequest(model: "m", messages: [])
        XCTAssertNil(bare.removingParametersRejected(by: LiteLLMError.httpError(status: 400, message: "`temperature` is deprecated")))
    }
}
