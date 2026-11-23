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
}
