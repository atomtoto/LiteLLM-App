import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var selection: UUID?
    @State private var showModels = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(conversations) { conversation in
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.title)
                                .lineLimit(1)
                            Text(conversation.updatedAt, format: .relative(presentation: .numeric))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tag(conversation.id)
                }
                .onDelete(perform: deleteConversations)
            }
            .navigationTitle("Conversations")
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: newConversation) {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("Nouvelle conversation")
                }
                ToolbarItem(placement: .navigation) {
                    Button { showModels = true } label: {
                        Image(systemName: "server.rack")
                    }
                    .help("Modèles disponibles sur le serveur")
                }
                ToolbarItem(placement: .navigation) {
                    Button { openSettings() } label: {
                        Image(systemName: "gear")
                    }
                    .help("Réglages")
                }
            }
        } detail: {
            if let conversation = conversations.first(where: { $0.id == selection }) {
                ChatView(conversation: conversation, settings: settings)
            } else {
                ContentUnavailableView {
                    Label("Aucune conversation", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Créez une conversation pour discuter avec vos modèles LiteLLM.")
                } actions: {
                    Button("Nouvelle conversation") { newConversation() }
                }
            }
        }
        .sheet(isPresented: $showModels) {
            ModelsView()
        }
    }

    private func newConversation() {
        let conversation = Conversation(model: settings.defaultModel)
        modelContext.insert(conversation)
        try? modelContext.save()
        selection = conversation.id
    }

    private func deleteConversations(at offsets: IndexSet) {
        let deleted = offsets.map { conversations[$0].id }
        for index in offsets {
            modelContext.delete(conversations[index])
        }
        try? modelContext.save()
        if let selection, deleted.contains(selection) {
            self.selection = nil
        }
    }
}
