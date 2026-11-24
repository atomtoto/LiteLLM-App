import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    let conversation: Conversation
    @ObservationIgnored private let settings: AppSettings

    var input = ""
    var isStreaming = false
    var showError = false
    var errorMessage = ""
    /// Incrémenté à chaque chunk reçu, pour déclencher le défilement automatique.
    var updateCounter = 0

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    /// Réponse en cours de génération (remplie chunk par chunk).
    @ObservationIgnored private var streamingMessage: ChatMessage?

    init(conversation: Conversation, settings: AppSettings) {
        self.conversation = conversation
        self.settings = settings
    }

    /// Modèle effectif : celui de la conversation, sinon celui par défaut des réglages.
    var model: String {
        conversation.model.isEmpty ? settings.defaultModel : conversation.model
    }

    /// Messages triés par position (l'ordre d'une relation SwiftData n'est pas garanti).
    var sortedMessages: [ChatMessage] {
        conversation.messages.sorted { $0.position < $1.position }
    }

    var canSend: Bool {
        !isStreaming && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Vrai si la dernière réponse peut être régénérée (dernier message = réponse terminée).
    var canRegenerate: Bool {
        !isStreaming && sortedMessages.last?.role == "assistant"
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard checkReady() else { return }
        input = ""

        let userMessage = ChatMessage(role: "user", content: text, position: nextPosition)
        conversation.messages.append(userMessage)
        if conversation.title == Conversation.defaultTitle {
            conversation.title = Self.makeTitle(from: text)
        }
        generateReply()
    }

    /// Envoie un texte proposé (suggestion de l'écran vide).
    func send(suggestion: String) {
        input = suggestion
        send()
    }

    /// Supprime la dernière réponse et la redemande au modèle.
    func regenerate() {
        guard canRegenerate, checkReady() else { return }
        if let last = sortedMessages.last, last.role == "assistant" {
            conversation.messages.removeAll { $0.id == last.id }
            conversation.modelContext?.delete(last)
        }
        generateReply()
    }

    func stop() {
        streamTask?.cancel()
    }

    // MARK: - Génération

    private var nextPosition: Int {
        (conversation.messages.map(\.position).max() ?? -1) + 1
    }

    private func checkReady() -> Bool {
        guard !model.isEmpty else {
            errorMessage = L10n.shared.t("Aucun modèle sélectionné. Choisissez-en un dans la barre d'outils ou définissez-en un par défaut dans les réglages.")
            showError = true
            return false
        }
        guard settings.makeClient() != nil else {
            errorMessage = L10n.shared.t("URL du serveur invalide — vérifiez les réglages.")
            showError = true
            return false
        }
        return true
    }

    /// Ajoute une réponse vide de l'assistant et la remplit en streaming.
    private func generateReply() {
        guard let client = settings.makeClient() else { return }
        let history = sortedMessages
        let assistantMessage = ChatMessage(role: "assistant", content: "", position: nextPosition)
        conversation.messages.append(assistantMessage)
        streamingMessage = assistantMessage
        conversation.updatedAt = Date()
        save()

        var dtos = history.map { ChatMessageDTO(role: $0.role, content: $0.content) }
        let systemPrompt = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemPrompt.isEmpty {
            dtos.insert(ChatMessageDTO(role: "system", content: systemPrompt), at: 0)
        }
        let request = ChatCompletionRequest(
            model: model,
            messages: dtos,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens > 0 ? settings.maxTokens : nil,
            stream: true
        )

        isStreaming = true
        updateCounter += 1
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let usage = try await client.streamChatCompletion(request: request) { chunk in
                    await self.apply(chunk: chunk)
                }
                assistantMessage.tokenUsage = usage?.totalTokens
                self.finishStreaming()
            } catch is CancellationError {
                self.finishStreaming()
            } catch let error as URLError where error.code == .cancelled {
                self.finishStreaming()
            } catch {
                if assistantMessage.content.isEmpty {
                    self.conversation.messages.removeAll { $0.id == assistantMessage.id }
                    self.conversation.modelContext?.delete(assistantMessage)
                    self.errorMessage = FriendlyError.message(for: error)
                    self.showError = true
                } else {
                    assistantMessage.content += L10n.shared.t("\n\n— *Erreur : %@*", error.localizedDescription)
                }
                self.finishStreaming()
            }
        }
    }

    private func finishStreaming() {
        streamingMessage = nil
        isStreaming = false
        conversation.updatedAt = Date()
        save()
    }

    private func apply(chunk: ChatCompletionChunk) {
        guard let message = streamingMessage else { return }
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

    /// Titre lisible : première ligne du message, coupée proprement.
    static func makeTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        guard firstLine.count > 48 else { return firstLine }
        return String(firstLine.prefix(47)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func save() {
        try? conversation.modelContext?.save()
    }
}
