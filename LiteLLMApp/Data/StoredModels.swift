import Foundation
import SwiftData

@Model
final class Conversation {
    static let defaultTitle = "Nouvelle conversation"

    @Attribute(.unique) var id: UUID
    var title: String
    var model: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(title: String = Conversation.defaultTitle, model: String = "") {
        self.id = UUID()
        self.title = title
        self.model = model
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class ChatMessage {
    var id: UUID
    var role: String
    var content: String
    var reasoning: String?
    var tokenUsage: Int?
    var position: Int
    var createdAt: Date
    var conversation: Conversation?

    init(role: String, content: String, reasoning: String? = nil, tokenUsage: Int? = nil, position: Int = 0) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.tokenUsage = tokenUsage
        self.position = position
        self.createdAt = Date()
    }
}
