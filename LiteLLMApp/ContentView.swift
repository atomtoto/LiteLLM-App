import SwiftUI
import SwiftData

/// Actions exposées aux menus de l'app (Fichier ▸ Nouvelle conversation, etc.).
struct AppActions {
    var newConversation: () -> Void
    var showProxy: () -> Void
    var showOnboarding: () -> Void
    var showModels: () -> Void
}

extension FocusedValues {
    @Entry var appActions: AppActions?
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var proxy: ProxyManager
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var selection: UUID?
    @State private var searchText = ""
    @State private var showModels = false
    @State private var showProxy = false
    @State private var showOnboarding = false
    @State private var renaming: Conversation?
    @State private var renameText = ""
    @State private var pendingDeletion: Conversation?

    private var t: (String) -> String { L10n.shared.t }

    /// L'app est-elle prête à discuter (un serveur et au moins un modèle connus) ?
    private var isConfigured: Bool {
        !settings.defaultModel.isEmpty || !settings.availableModels.isEmpty
    }

    private var filteredConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter { conversation in
            displayTitle(conversation).localizedStandardContains(query)
                || conversation.messages.contains { $0.content.localizedStandardContains(query) }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Pas de bandeau tant que l'app n'est pas configurée : l'écran d'accueil s'en charge.
                    if isConfigured {
                        ConnectionBanner(
                        onOpenProxy: { showProxy = true },
                            onOpenOnboarding: { showOnboarding = true }
                        )
                    }
                }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showProxy = true } label: {
                    Label(t("Fournisseurs d'IA"), systemImage: proxy.isRunning ? "cpu.fill" : "cpu")
                }
                .help(t("Gérer le service IA local : fournisseurs, clés API, démarrage"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(t("Assistant de configuration…"), systemImage: "wand.and.stars") { showOnboarding = true }
                    Button(t("Modèles disponibles…"), systemImage: "list.bullet") { showModels = true }
                    Divider()
                    SettingsLink {
                        Label(t("Réglages…"), systemImage: "gear")
                    }
                } label: {
                    Label(t("Plus"), systemImage: "ellipsis.circle")
                }
                .help(t("Configuration"))
            }
        }
        .focusedSceneValue(\.appActions, AppActions(
            newConversation: newConversation,
            showProxy: { showProxy = true },
            showOnboarding: { showOnboarding = true },
            showModels: { showModels = true }
        ))
        .sheet(isPresented: $showModels) {
            ModelsView()
        }
        .sheet(isPresented: $showProxy) {
            ProxyView()
                .environmentObject(settings)
                .environmentObject(proxy)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(onOpenChat: { newConversation() })
                .environmentObject(settings)
                .environmentObject(proxy)
        }
        .alert(t("Renommer la conversation"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField(t("Titre"), text: $renameText)
            Button(t("Renommer")) {
                let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let renaming, !title.isEmpty {
                    renaming.title = title
                    try? modelContext.save()
                }
                renaming = nil
            }
            Button(t("Annuler"), role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            L10n.shared.t("Supprimer « %@ » ?", pendingDeletion.map(displayTitle) ?? ""),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button(t("Supprimer"), role: .destructive) {
                if let pendingDeletion { delete(pendingDeletion) }
                pendingDeletion = nil
            }
        } message: {
            Text(t("Cette action est définitive."))
        }
        .onChange(of: proxy.isRunning) { _, running in
            // Le service vient de (re)démarrer : ses modèles ont pu changer.
            if running, settings.isConnected(to: proxy.baseURL) {
                Task { await settings.refreshAvailableModels() }
            }
        }
        .task {
            proxy.autoStartIfNeeded()
            if !OnboardingState.hasCompleted {
                showOnboarding = true
            } else if selection == nil {
                selection = conversations.first?.id
            }
        }
    }

    // MARK: - Barre latérale

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(filteredConversations) { conversation in
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle(conversation))
                        .lineLimit(1)
                    Text(conversation.updatedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(conversation.id)
                .contextMenu {
                    Button(t("Renommer…"), systemImage: "pencil") {
                        renameText = displayTitle(conversation)
                        renaming = conversation
                    }
                    Button(t("Supprimer"), systemImage: "trash", role: .destructive) {
                        pendingDeletion = conversation
                    }
                }
            }
        }
        .overlay {
            if conversations.isEmpty {
                ContentUnavailableView(t("Aucune conversation"), systemImage: "bubble.left.and.bubble.right")
            } else if filteredConversations.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: t("Rechercher"))
        .onDeleteCommand {
            if let conversation = conversations.first(where: { $0.id == selection }) {
                pendingDeletion = conversation
            }
        }
        .navigationTitle(t("Conversations"))
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .toolbar {
            ToolbarItem {
                Button(action: newConversation) {
                    Label(t("Nouvelle conversation"), systemImage: "square.and.pencil")
                }
                .help(t("Nouvelle conversation (⌘N)"))
            }
        }
    }

    // MARK: - Détail

    @ViewBuilder
    private var detail: some View {
        if let conversation = conversations.first(where: { $0.id == selection }) {
            ChatView(conversation: conversation, settings: settings)
                // Une nouvelle identité par conversation : le view model est recréé
                // au lieu de continuer à écrire dans la conversation précédente.
                .id(conversation.id)
        } else if !isConfigured {
            ContentUnavailableView {
                Label(t("Bienvenue !"), systemImage: "sparkles")
            } description: {
                Text(t("Pour commencer, connectez un fournisseur d'IA (OpenAI, Anthropic, Gemini, Mistral, Ollama…). L'assistant vous guide en quelques étapes."))
            } actions: {
                Button(t("Configurer maintenant")) { showOnboarding = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else {
            ContentUnavailableView {
                Label(t("Aucune conversation sélectionnée"), systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text(t("Créez une conversation pour discuter avec l'IA."))
            } actions: {
                Button(t("Nouvelle conversation")) { newConversation() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    // MARK: - Actions

    private func displayTitle(_ conversation: Conversation) -> String {
        conversation.title == Conversation.defaultTitle ? t("Nouvelle conversation") : conversation.title
    }

    private func newConversation() {
        // Réutilise une conversation vide existante plutôt que d'en empiler.
        if let empty = conversations.first(where: { $0.messages.isEmpty }) {
            selection = empty.id
            return
        }
        let conversation = Conversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        searchText = ""
        selection = conversation.id
    }

    private func delete(_ conversation: Conversation) {
        if selection == conversation.id { selection = nil }
        modelContext.delete(conversation)
        try? modelContext.save()
    }
}

/// Bandeau affiché en haut du chat quand le service IA n'est pas utilisable,
/// avec l'action qui résout le problème en un clic.
private struct ConnectionBanner: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var proxy: ProxyManager
    var onOpenProxy: () -> Void
    var onOpenOnboarding: () -> Void

    private var t: (String) -> String { L10n.shared.t }

    /// L'app utilise-t-elle le proxy local géré par l'app ?
    private var usesLocalProxy: Bool {
        settings.isConnected(to: proxy.baseURL)
    }

    var body: some View {
        if usesLocalProxy, !proxy.isRunning {
            HStack(spacing: 10) {
                banner
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    @ViewBuilder
    private var banner: some View {
        switch proxy.state {
        case .running:
            EmptyView()
        case .starting, .installing, .stopping:
            ProgressView().controlSize(.small)
            message(proxy.state == .installing
                    ? t("Installation du service IA… (quelques minutes la première fois)")
                    : t("Démarrage du service IA…"))
        case .installed:
            Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            message(t("Le service IA est arrêté."))
            Button(t("Démarrer")) { proxy.start() }
                .buttonStyle(.borderedProminent)
        case .notInstalled:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            message(t("Le service IA n'est pas encore installé."))
            Button(t("Configurer"), action: onOpenOnboarding)
                .buttonStyle(.borderedProminent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            message(t("Le service IA a rencontré un problème."))
            Button(t("Voir les détails"), action: onOpenProxy)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity, alignment: .leading)
    }
}
