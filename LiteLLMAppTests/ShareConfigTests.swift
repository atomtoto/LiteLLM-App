import XCTest
import Foundation

final class ShareConfigTests: XCTestCase {
    func testSnippetContainsAllParts() {
        let l10n = L10n()
        l10n.lang = .fr
        let text = ShareConfig.snippet(baseURL: "http://127.0.0.1:4000/", apiKey: "sk-master", model: "gpt-4o", l10n: l10n)
        XCTAssertTrue(text.contains("http://127.0.0.1:4000/v1"))
        XCTAssertTrue(text.contains("sk-master"))
        XCTAssertTrue(text.contains("gpt-4o"))
        XCTAssertTrue(text.contains("curl http://127.0.0.1:4000/v1/chat/completions"))
        XCTAssertTrue(text.contains("Authorization: Bearer sk-master"))
        // le slash final de la base est normalisé
        XCTAssertFalse(text.contains("4000//v1"))
    }

    func testSnippetEnglish() {
        let l10n = L10n()
        l10n.lang = .en
        let text = ShareConfig.snippet(baseURL: "http://localhost:4000", apiKey: "sk-x", model: "m", l10n: l10n)
        XCTAssertTrue(text.contains("Base URL:"))
        XCTAssertTrue(text.contains("API key:"))
        XCTAssertTrue(text.contains("Sample request"))
    }

    func testCodexCommandDeclaresLiteLLMProvider() {
        let cmd = ShareConfig.command(for: .codex, baseURL: "http://127.0.0.1:4000/", apiKey: "sk-master", model: "claude")
        XCTAssertTrue(cmd.contains("LITELLM_API_KEY='sk-master' codex"))
        XCTAssertTrue(cmd.contains("-c model_provider=litellm"))
        XCTAssertTrue(cmd.contains("base_url = \"http://127.0.0.1:4000/v1\""))
        XCTAssertTrue(cmd.contains("wire_api = \"responses\""))
        XCTAssertTrue(cmd.contains("-m 'claude'"))
    }

    func testClaudeCodeCommandUsesAnthropicVariables() {
        let cmd = ShareConfig.command(for: .claudeCode, baseURL: "http://127.0.0.1:4000", apiKey: "sk-master", model: "mistral-large")
        XCTAssertTrue(cmd.contains("ANTHROPIC_BASE_URL='http://127.0.0.1:4000'"))
        XCTAssertTrue(cmd.contains("ANTHROPIC_AUTH_TOKEN='sk-master'"))
        XCTAssertTrue(cmd.contains("ANTHROPIC_MODEL='mistral-large'"))
        XCTAssertTrue(cmd.hasSuffix("claude"))
    }

    func testShellQuoteEscapesSingleQuotes() {
        XCTAssertEqual(ShareConfig.shellQuote("it's"), "'it'\\''s'")
    }

    func testLaunchScriptChecksExecutable() {
        let l10n = L10n()
        l10n.lang = .fr
        let script = ShareConfig.launchScript(for: .codex, baseURL: "http://127.0.0.1:4000", apiKey: "k", model: "m", l10n: l10n)
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
        XCTAssertTrue(script.contains("command -v codex"))
        XCTAssertTrue(script.contains("npm install -g @openai/codex"))
    }

    func testCodexAppEnableDisableRoundTrip() {
        let original = """
        model = "gpt-6.2"
        model_reasoning_effort = "xhigh"
        sandbox_mode = "workspace-write"

        [features]
        memories = true
        """
        let enabled = CodexAppConfig.enable(in: original, baseURL: "http://127.0.0.1:4000", apiKey: "sk-master", model: "claude")
        XCTAssertTrue(CodexAppConfig.isEnabled(enabled))
        XCTAssertEqual(CodexAppConfig.enabledModel(enabled), "claude")
        XCTAssertTrue(enabled.hasPrefix("model = \"claude\" # LiteLLM-App\nmodel_provider = \"litellm-app\""))
        XCTAssertTrue(enabled.contains("# LiteLLM-App: model = \"gpt-6.2\""))
        XCTAssertTrue(enabled.contains("# LiteLLM-App: model_reasoning_effort"))
        XCTAssertTrue(enabled.contains("experimental_bearer_token = \"sk-master\""))
        XCTAssertTrue(enabled.contains("base_url = \"http://127.0.0.1:4000/v1\""))
        // Réactiver est idempotent, désactiver restaure l'original.
        XCTAssertEqual(CodexAppConfig.enable(in: enabled, baseURL: "http://127.0.0.1:4000", apiKey: "sk-master", model: "claude"), enabled)
        XCTAssertEqual(CodexAppConfig.disable(in: enabled), original + "\n")
    }

    func testCodexAppDisableKeepsModelChangedMeanwhile() {
        var toml = CodexAppConfig.enable(in: "model = \"gpt\"\n", baseURL: "http://h:1", apiKey: "k", model: "claude")
        // L'app Codex a réécrit le modèle sans notre marqueur.
        toml = toml.replacingOccurrences(of: "model = \"claude\" # LiteLLM-App", with: "model = \"other\"")
        let restored = CodexAppConfig.disable(in: toml)
        XCTAssertTrue(restored.contains("model = \"other\""))
        XCTAssertFalse(restored.contains("model = \"gpt\""))
        XCTAssertFalse(restored.contains("litellm-app"))
    }

    func testCodexAppEnableOnEmptyConfig() {
        let enabled = CodexAppConfig.enable(in: "", baseURL: "http://h:1", apiKey: "k", model: "m")
        XCTAssertTrue(CodexAppConfig.isEnabled(enabled))
        XCTAssertEqual(CodexAppConfig.disable(in: enabled).trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testCodexLaunchScriptFallsBackToEmbeddedCLI() {
        let script = ShareConfig.launchScript(for: .codex, baseURL: "http://h:1", apiKey: "k", model: "m")
        XCTAssertTrue(script.contains("elif [ -x '/Applications/ChatGPT.app/"))
    }
}
