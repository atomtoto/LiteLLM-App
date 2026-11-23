import SwiftUI
import AppKit

struct MessageRow: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isUser ? "person.circle.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(isUser ? Color.accentColor : .purple)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                if !isUser, let reasoning = message.reasoning, !reasoning.isEmpty {
                    DisclosureGroup {
                        Text(reasoning)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } label: {
                        Text("Raisonnement")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if message.content.isEmpty && !isUser {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    messageBody
                }
                if let tokenUsage = message.tokenUsage {
                    Text("\(tokenUsage) tokens")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(message.content, forType: .string)
            } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        if let attributed = try? AttributedString(markdown: message.content) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(message.content)
                .textSelection(.enabled)
        }
    }
}
