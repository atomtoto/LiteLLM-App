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
}
