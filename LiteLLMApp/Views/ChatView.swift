import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var settings: AppSettings
    let conversation: Conversation
    @State private var vm: ChatViewModel
    @State private var showParameters = false

    init(conversation: Conversation, settings: AppSettings) {
        self.conversation = conversation
        self._vm = State(initialValue: ChatViewModel(conversation: conversation, settings: settings))
    }

    private var t: (String) -> String { L10n.shared.t }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messages
            Divider()
            composer
        }
        .navigationTitle(conversation.title == Conversation.defaultTitle ? t("Nouvelle conversation") : conversation.title)
        .alert(t("Erreur"), isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    // MARK: - En-tête : modèle + paramètres

    private var modelBinding: Binding<String> {
        Binding(
            get: { conversation.model },
            set: { conversation.model = $0 }
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker(t("Modèle"), selection: modelBinding) {
                Text(t("Par défaut")).tag("")
                if !conversation.model.isEmpty && !settings.availableModels.contains(conversation.model) {
                    Text(conversation.model).tag(conversation.model)
                }
                ForEach(settings.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 380)
            Spacer()
            Button { showParameters.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help(t("Paramètres de génération"))
            .popover(isPresented: $showParameters) {
                parametersPopover
                    .padding()
                    .frame(width: 360)
            }
            Button { Task { await refreshModels() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(t("Actualiser la liste des modèles depuis le serveur"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var parametersPopover: some View {
        Form {
            Section(t("Génération")) {
                HStack {
                    Text(t("Température"))
                    Slider(value: $settings.temperature, in: 0...2, step: 0.05)
                    Text(settings.temperature, format: .number.precision(.fractionLength(2)))
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $settings.maxTokens, in: 16...200_000, step: 256) {
                    Text(L10n.shared.t("Tokens max : %@", settings.maxTokens))
                }
            }
            Section(t("Invite système")) {
                TextField(t("Invite système (optionnel)"), text: $settings.systemPrompt, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .formStyle(.grouped)
    }

    private func refreshModels() async {
        guard let client = settings.makeClient() else { return }
        do {
            let models = try await client.listModels()
            settings.availableModels = models.map(\.id).sorted()
        } catch {
            vm.errorMessage = L10n.shared.t("Impossible de récupérer les modèles : %@", error.localizedDescription)
            vm.showError = true
        }
    }

    // MARK: - Messages

    private var sortedMessages: [ChatMessage] {
        conversation.messages.sorted { $0.position < $1.position }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(sortedMessages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.updateCounter) { _, _ in
                if let last = sortedMessages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Zone de saisie

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextEditor(text: $vm.input)
                .font(.body)
                .frame(minHeight: 36, maxHeight: 180)
                .scrollDisabled(true)
            Button {
                if vm.isStreaming { vm.stop() } else { vm.send() }
            } label: {
                Image(systemName: vm.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!vm.isStreaming && vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(vm.isStreaming ? t("Arrêter la génération") : t("Envoyer (⌘↩)"))
        }
        .padding(12)
    }
}
