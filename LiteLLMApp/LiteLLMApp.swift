import SwiftUI
import SwiftData

@main
struct LiteLLMApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var proxy = ProxyManager()

    init() {
        // Avant toute lecture des clés (AppSettings, ProxyManager).
        KeychainService.migrateLegacyItemsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(proxy)
                .frame(minWidth: 760, minHeight: 480)
        }
        .modelContainer(for: [Conversation.self, ChatMessage.self])
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(proxy)
        }
    }
}

/// Entrées de menu : Fichier ▸ Nouvelle conversation (⌘N), et accès rapide à la configuration.
private struct AppCommands: Commands {
    @FocusedValue(\.appActions) private var actions

    private var t: (String) -> String { L10n.shared.t }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(t("Nouvelle conversation")) { actions?.newConversation() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }
        CommandMenu(t("IA")) {
            Button(t("Fournisseurs d'IA…")) { actions?.showProxy() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button(t("Modèles disponibles…")) { actions?.showModels() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button(t("Utiliser avec d'autres apps…")) { actions?.showExternalTools() }
            Divider()
            Button(t("Assistant de configuration…")) { actions?.showOnboarding() }
        }
    }
}
