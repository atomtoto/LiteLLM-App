import XCTest
import Foundation

final class ProxyConfigTests: XCTestCase {
    func testQuoteEscapesBackslashAndQuotes() {
        XCTAssertEqual(YAMLEmitter.quote("sk-abc"), "\"sk-abc\"")
        XCTAssertEqual(YAMLEmitter.quote("a\"b\\c"), "\"a\\\"b\\\\c\"")
        XCTAssertEqual(YAMLEmitter.quote(""), "\"\"")
    }

    func testRenderConfigWithModels() {
        let settings = ProxySettingsData(models: [
            ProxyModel(name: "gpt-4o", providerModel: "openai/gpt-4o", apiKey: "sk-test\"1"),
            ProxyModel(name: "llama3", providerModel: "ollama/llama3", apiKey: "", apiBase: "http://127.0.0.1:11434"),
        ])
        let yaml = YAMLEmitter.renderConfig(settings: settings, masterKey: "sk-master")

        XCTAssertTrue(yaml.contains("model_list:"))
        XCTAssertTrue(yaml.contains("- model_name: \"gpt-4o\""))
        XCTAssertTrue(yaml.contains("model: \"openai/gpt-4o\""))
        XCTAssertTrue(yaml.contains("api_key: \"sk-test\\\"1\"")) // clé échappée
        XCTAssertTrue(yaml.contains("model: \"ollama/llama3\""))
        XCTAssertTrue(yaml.contains("api_base: \"http://127.0.0.1:11434\""))
        XCTAssertTrue(yaml.contains("master_key: \"sk-master\""))
        XCTAssertTrue(yaml.contains("drop_params: true"))
        // pas de api_key vide pour ollama
        let ollamaBlock = yaml.components(separatedBy: "- model_name: \"llama3\"").last ?? ""
        XCTAssertFalse(ollamaBlock.contains("api_key"))
    }

    func testRenderConfigSkipsIncompleteModels() {
        let settings = ProxySettingsData(models: [
            ProxyModel(name: "", providerModel: "openai/gpt-4o", apiKey: "sk-x"),
            ProxyModel(name: "ok", providerModel: "", apiKey: "sk-x"),
        ])
        let yaml = YAMLEmitter.renderConfig(settings: settings, masterKey: "")
        XCTAssertTrue(yaml.contains("model_list: []"))
        XCTAssertFalse(yaml.contains("master_key"))
    }

    func testRenderedYamlIsParseable() throws {
        // Validation via Foundation (YAML natif macOS 13+ n'est pas exposé en Swift public,
        // on vérifie la structure ligne à ligne à la place).
        let settings = ProxySettingsData(port: 4000, models: [
            ProxyModel(name: "a", providerModel: "openai/a", apiKey: "k"),
        ])
        let yaml = YAMLEmitter.renderConfig(settings: settings, masterKey: "m")
        let lines = yaml.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains("model_list:"))
        XCTAssertTrue(lines.contains("general_settings:"))
        XCTAssertTrue(lines.contains("litellm_settings:"))
        XCTAssertTrue(lines.contains("  master_key: \"m\""))
    }

    func testSettingsStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("proxy-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        var data = ProxySettingsData(host: "127.0.0.1", port: 4123, stopOnQuit: false, autoStart: true,
                                     models: [ProxyModel(name: "m", providerModel: "openai/m", apiKey: "k")])
        ProxySettingsStore.save(data, to: url)
        let loaded = ProxySettingsStore.load(from: url)
        XCTAssertEqual(loaded, data)
    }

    func testConfigWriterSetsRestrictivePermissions() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("litellm-app-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.yaml")

        let yaml = try ProxyConfigWriter.write(
            settings: ProxySettingsData(models: [ProxyModel(name: "m", providerModel: "openai/m", apiKey: "k")]),
            masterKey: "sk-master",
            to: url)
        XCTAssertTrue(yaml.contains("master_key: \"sk-master\""))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = attrs[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func testConfigLoadsCodexCompatibilityHooks() throws {
        let settings = ProxySettingsData(models: [
            ProxyModel(name: "gpt", providerModel: "openai/gpt-5"),
            ProxyModel(name: "claude", providerModel: "anthropic/claude-opus-5-5"),
        ])
        let yaml = YAMLEmitter.renderConfig(settings: settings, masterKey: "k")
        XCTAssertTrue(yaml.contains("  callbacks: litellm_app_hooks.proxy_handler_instance"))
        let hooks = YAMLEmitter.renderHooks(settings: settings)
        XCTAssertTrue(hooks.contains("NATIVE_MODELS = {\"gpt\"}"))
        XCTAssertTrue(hooks.contains("proxy_handler_instance = LiteLLMAppHooks()"))
        XCTAssertTrue(hooks.contains("\n    async def async_pre_call_hook("))

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try ProxyConfigWriter.write(settings: settings, masterKey: "k", to: dir.appendingPathComponent("config.yaml"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("litellm_app_hooks.py").path))
    }
}
