import XCTest
import Foundation

final class LocalizationTests: XCTestCase {
    func testFrenchReturnsKeyAsIs() {
        let l10n = L10n()
        l10n.lang = .fr
        XCTAssertEqual(l10n.t("Copier"), "Copier")
        XCTAssertEqual(l10n.t("Nouvelle conversation"), "Nouvelle conversation")
    }

    func testEnglishTranslatesKnownKeys() {
        let l10n = L10n()
        l10n.lang = .en
        XCTAssertEqual(l10n.t("Copier"), "Copy")
        XCTAssertEqual(l10n.t("Nouvelle conversation"), "New conversation")
        XCTAssertEqual(l10n.t("Réglages"), "Settings")
    }

    func testUnknownKeyFallsBackToKey() {
        let l10n = L10n()
        l10n.lang = .en
        XCTAssertEqual(l10n.t("Une clé inexistante"), "Une clé inexistante")
    }

    func testFormattingWithArgs() {
        let l10n = L10n()
        l10n.lang = .fr
        XCTAssertEqual(l10n.t("%@ tokens", 42), "42 tokens")
        l10n.lang = .en
        XCTAssertEqual(l10n.t("%@ tokens", 42), "42 tokens")
        XCTAssertEqual(l10n.t("Étape %@ sur %@", 2, 6), "Step 2 of 6")
    }

    func testLanguagePersistsInUserDefaults() {
        let l10n = L10n()
        l10n.lang = .en
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appLanguage"), "en")
        l10n.lang = .fr
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appLanguage"), "fr")
    }

    func testFormattingNeverCrashesOnNonObjectArguments() {
        let l10n = L10n()
        l10n.lang = .fr
        XCTAssertEqual(l10n.t("Tokens max : %@", 1024), "Tokens max : 1024")
        XCTAssertEqual(l10n.t("%@ modèle(s) en cache", 3), "3 modèle(s) en cache")
        // Relais d'arguments variadiques (helpers `tf` des vues).
        let args: [Any] = [1, 6]
        XCTAssertEqual(l10n.t("Étape %@ sur %@", arguments: args), "Étape 1 sur 6")
        // Arguments manquants : le marqueur est laissé tel quel plutôt que de planter.
        XCTAssertEqual(l10n.t("Étape %@ sur %@", arguments: [1]), "Étape 1 sur %@")
    }
}
