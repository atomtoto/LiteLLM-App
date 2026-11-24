import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var settings: AppSettings
    let conversation: Conversation
    @State private var vm: ChatViewModel
    @State private var showParameters = false
    @FocusState private var composerFocused: Bool

    init(conversation: Conversation, settings: AppSettings) {
        self.conversation = conversation
        self._vm = State(initialValue: ChatViewModel(conversation: conversation, settings: settings))
    }

    private var t: (String) -> String { L10n.shared.t }

    var body: some View {
        messages
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .navigationTitle(conversation.title == Conversation.defaultTitle ? t("Nouvelle conversation") : conversation.title)
            .toolbar { toolbarContent }
            .alert(t("Erreur"), isPresented: $vm.showError) {
                Button(t("OK"), role: .cancel) {}
            } message: {
                Text(vm.errorMessage)
            }
            .task {
                composerFocused = true
                if settings.availableModels.isEmpty {
                    await refreshModels(showErrors: false)
                }
            }
    }

    // MARK: - Barre d'outils : modèle + paramètres

    private var modelBinding: Binding<String> {
        Binding(
            get: { conversation.model },
            set: { conversation.model = $0 }
        )
    }

    private var defaultModelLabel: String {
        settings.defaultModel.isEmpty
            ? t("Par défaut")
            : L10n.shared.t("Par défaut (%@)", settings.defaultModel)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker(t("Modèle"), selection: modelBinding) {
                Text(defaultModelLabel).tag("")
                if !conversation.model.isEmpty && !settings.availableModels.contains(conversation.model) {
                    Text(conversation.model).tag(conversation.model)
                }
                if !settings.availableModels.isEmpty {
                    Divider()
                    ForEach(settings.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }
            .pickerStyle(.menu)
            .help(t("Modèle utilisé pour cette conversation"))
        }
        ToolbarItem {
            Button { showParameters.toggle() } label: {
                Label(t("Paramètres de génération"), systemImage: "slider.horizontal.3")
            }
            .help(t("Paramètres de génération"))
            .popover(isPresented: $showParameters) {
                GenerationSettingsForm()
                    .frame(width: 380)
                    .padding(.vertical, 8)
            }
        }
    }

    private func refreshModels(showErrors: Bool = true) async {
        guard let client = settings.makeClient() else { return }
        do {
            let models = try await client.listModels()
            settings.availableModels = models.map(\.id).sorted()
        } catch where showErrors {
            vm.errorMessage = FriendlyError.message(for: error)
            vm.showError = true
        } catch {}
    }

    // MARK: - Messages

    @ViewBuilder
    private var messages: some View {
        let sorted = vm.sortedMessages
        if sorted.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(sorted) { message in
                            MessageRow(
                                message: message,
                                isStreaming: vm.isStreaming && message.id == sorted.last?.id,
                                onRegenerate: message.id == sorted.last?.id && vm.canRegenerate
                                    ? { vm.regenerate() } : nil
                            )
                            .id(message.id)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: vm.updateCounter) { _, _ in
                    if let last = sorted.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Écran d'une conversation vide : quelques idées pour démarrer en un clic.
    private var emptyState: some View {
        ContentUnavailableView {
            Label(t("Posez votre question"), systemImage: "sparkles")
        } description: {
            Text(vm.model.isEmpty
                 ? t("Choisissez d'abord un modèle dans la barre d'outils.")
                 : L10n.shared.t("Vous discutez avec %@. Écrivez un message ci-dessous ou essayez une idée :", vm.model))
        } actions: {
            VStack(alignment: .leading) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { vm.send(suggestion: suggestion) }
                }
            }
            .disabled(vm.model.isEmpty)
        }
    }

    private var suggestions: [String] {
        [
            t("Explique-moi simplement comment fonctionne l'IA."),
            t("Aide-moi à rédiger un e-mail poli pour décliner une invitation."),
            t("Donne-moi 5 idées de repas rapides pour la semaine."),
        ]
    }

    // MARK: - Zone de saisie

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(t("Écrivez votre message…"), text: $vm.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($composerFocused)
                .onSubmit { vm.send() }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .accessibilityLabel(t("Message"))
            if vm.isStreaming {
                Button { vm.stop() } label: {
                    Label(t("Arrêter la génération"), systemImage: "stop.fill")
                }
                .keyboardShortcut(.escape, modifiers: [])
                .help(t("Arrêter la génération (Échap)"))
            } else {
                Button { vm.send() } label: {
                    Label(t("Envoyer"), systemImage: "arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!vm.canSend)
                .help(t("Envoyer (Entrée) — ⌥Entrée pour aller à la ligne"))
            }
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
        .padding(12)
        .background(.bar)
    }
}

/// Réglages de génération partagés par le popover du chat et la fenêtre Réglages.
struct GenerationSettingsForm: View {
    @EnvironmentObject private var settings: AppSettings

    private var t: (String) -> String { L10n.shared.t }

    private var limitBinding: Binding<Bool> {
        Binding(
            get: { settings.maxTokens > 0 },
            set: { settings.maxTokens = $0 ? 4096 : 0 }
        )
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Slider(value: $settings.temperature, in: 0...2, step: 0.1) {
                        Text(t("Créativité"))
                    } minimumValueLabel: {
                        Text(t("Précis"))
                    } maximumValueLabel: {
                        Text(t("Créatif"))
                    }
                    .labelsHidden()
                } label: {
                    Text(t("Créativité"))
                    Text(L10n.shared.t("Température : %@", settings.temperature.formatted(.number.precision(.fractionLength(1)))))
                }
                Toggle(t("Limiter la longueur des réponses"), isOn: limitBinding)
                if settings.maxTokens > 0 {
                    Stepper(value: $settings.maxTokens, in: 16...200_000, step: 256) {
                        Text(L10n.shared.t("Tokens max : %@", settings.maxTokens))
                    }
                }
            } header: {
                Text(t("Génération"))
            }
            Section {
                TextField(t("Invite système"), text: $settings.systemPrompt,
                          prompt: Text(t("Ex. : Réponds toujours en français, de façon concise.")),
                          axis: .vertical)
                    .lineLimit(2...6)
                    .labelsHidden()
            } header: {
                Text(t("Instructions permanentes"))
            } footer: {
                Text(t("Ces instructions sont envoyées au modèle au début de chaque conversation."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
