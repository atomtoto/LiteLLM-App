import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    let conversation: Conversation
    private let settings: AppSettings

    @Published var input = ""
    @Published var isStreaming = false
    @Published var showError = false
    @Published var errorMessage = ""
    /// Incrémenté à chaque chunk reçu, pour déclencher le défilement automatique.
    @Published var updateCounter = 0

    private var streamTask: Task<Void, Never>?

    init(conversation: Conversation, settings: AppSettings) {
        self.conversation = conversation
        self.settings = settings
    }

    /// Modèle effectif : celui de la conversation, sinon celui par défaut des réglages.
    var model: String {
        conversation.model.isEmpty ? settings.defaultModel : conversation.model
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard !model.isEmpty else {
            errorMessage = L10n.shared.t("Aucun modèle sélectionné. Choisissez-en un dans la barre d'outils ou définissez-en un par défaut dans les réglages.")
            showError = true
            return
        }
        guard let client = settings.makeClient() else {
            errorMessage = L10n.shared.t("URL du serveur invalide — vérifiez les réglages.")
            showError = true
            return
        }
        input = ""

        let userMessage = ChatMessage(role: "user", content: text,
                                      position: (conversation.messages.last?.position ?? -1) + 1)
        let assistantMessage = ChatMessage(role: "assistant", content: "",
                                           position: userMessage.position + 1)
        conversation.messages.append(userMessage)
        conversation.messages.append(assistantMessage)
        if conversation.title == Conversation.defaultTitle {
            conversation.title = String(text.prefix(48))
        }
        conversation.updatedAt = Date()
        save()

        var dtos = conversation.messages
            .dropLast()
            .map { ChatMessageDTO(role: $0.role, content: $0.content) }
        let systemPrompt = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemPrompt.isEmpty {
            dtos.insert(ChatMessageDTO(role: "system", content: systemPrompt), at: 0)
        }
        let request = ChatCompletionRequest(
            model: model,
            messages: dtos,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens,
            stream: true
        )

        isStreaming = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let usage = try await client.streamChatCompletion(request: request) { chunk in
                    Task { @MainActor in
                        self.apply(chunk: chunk, to: assistantMessage)
                    }
                }
                await MainActor.run {
                    assistantMessage.tokenUsage = usage?.totalTokens
                    self.isStreaming = false
                    self.conversation.updatedAt = Date()
                    self.save()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isStreaming = false
                    self.save()
                }
            } catch {
                await MainActor.run {
                    self.isStreaming = false
                    if assistantMessage.content.isEmpty {
                        self.conversation.messages.removeAll { $0.id == assistantMessage.id }
                        self.errorMessage = error.localizedDescription
                        self.showError = true
                    } else {
                        assistantMessage.content += L10n.shared.t("\n\n— *Erreur : %@*", error.localizedDescription)
                    }
                    self.save()
                }
            }
        }
    }

    func stop() {
        streamTask?.cancel()
    }

    private func apply(chunk: ChatCompletionChunk, to message: ChatMessage) {
        for choice in chunk.choices {
            if let content = choice.delta.content {
                message.content += content
            }
            if let reasoning = choice.delta.reasoningContent {
                message.reasoning = (message.reasoning ?? "") + reasoning
            }
        }
        updateCounter += 1
    }

    private func save() {
        try? conversation.modelContext?.save()
    }
}
