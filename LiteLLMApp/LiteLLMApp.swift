import SwiftUI
import SwiftData

@main
struct LiteLLMApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var proxy = ProxyManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(proxy)
        }
        .modelContainer(for: [Conversation.self, ChatMessage.self])

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
