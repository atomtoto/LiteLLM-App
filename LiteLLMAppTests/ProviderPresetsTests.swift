import XCTest
import Foundation

final class ProviderPresetsTests: XCTestCase {
    func testDetectAnthropicKey() {
        let p = ProviderPresets.detect(fromAPIKey: "sk-ant-api03-xxxx")
        XCTAssertEqual(p?.id, "anthropic")
    }

    func testDetectGeminiKey() {
        let p = ProviderPresets.detect(fromAPIKey: "AIzaSyD-1234567890")
        XCTAssertEqual(p?.id, "gemini")
    }

    func testDetectOpenAIProjectKey() {
        let p = ProviderPresets.detect(fromAPIKey: "sk-proj-abcdef")
        XCTAssertEqual(p?.id, "openai")
    }

    func testDetectUnknownKeyReturnsNil() {
        XCTAssertNil(ProviderPresets.detect(fromAPIKey: "une-cle-aleatoire"))
        XCTAssertNil(ProviderPresets.detect(fromAPIKey: "   "))
    }

    func testPresetForProviderModel() {
        XCTAssertEqual(ProviderPresets.preset(forProviderModel: "openai/gpt-4o").id, "openai")
        XCTAssertEqual(ProviderPresets.preset(forProviderModel: "anthropic/claude-sonnet-4-5").id, "anthropic")
        XCTAssertEqual(ProviderPresets.preset(forProviderModel: "ollama/llama3.3").id, "ollama")
        XCTAssertEqual(ProviderPresets.preset(forProviderModel: "azure/mon-deploiement").id, "azure")
        XCTAssertEqual(ProviderPresets.preset(forProviderModel: "qqchose/autre").id, "custom")
    }

    func testBareModelID() {
        XCTAssertEqual(ProviderPresets.bareModelID(from: "openai/gpt-4o"), "gpt-4o")
        XCTAssertEqual(ProviderPresets.bareModelID(from: "gpt-4o"), "gpt-4o")
        XCTAssertEqual(ProviderPresets.bareModelID(from: "ollama/qwen3:latest"), "qwen3:latest")
    }

    func testFullModel() {
        let openai = ProviderPresets.preset(id: "openai")
        XCTAssertEqual(ProviderPresets.fullModel(preset: openai, modelID: "gpt-4o"), "openai/gpt-4o")
    }

    func testPresetsHaveKnownModelsAndPrefixes() {
        for preset in ProviderPresets.all where preset.id != "custom" {
            XCTAssertFalse(preset.litellmPrefix.isEmpty, "\(preset.id) doit avoir un préfixe LiteLLM")
        }
        XCTAssertFalse(ProviderPresets.preset(id: "openai").knownModels.isEmpty)
        XCTAssertFalse(ProviderPresets.preset(id: "ollama").requiresAPIKey)
        XCTAssertTrue(ProviderPresets.preset(id: "anthropic").requiresAPIKey)
        XCTAssertEqual(ProviderPresets.preset(id: "ollama").defaultAPIBase, "http://127.0.0.1:11434")
    }
}
