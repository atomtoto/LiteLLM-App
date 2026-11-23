import SwiftUI
import SwiftData

@main
struct LiteLLMApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
        .modelContainer(for: [Conversation.self, ChatMessage.self])

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
