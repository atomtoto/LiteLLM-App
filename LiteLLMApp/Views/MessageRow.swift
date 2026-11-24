import SwiftUI
import AppKit

struct MessageRow: View {
    let message: ChatMessage
    /// Vrai pendant que cette réponse est en cours de génération.
    var isStreaming = false
    /// Fourni uniquement pour la dernière réponse, quand elle peut être régénérée.
    var onRegenerate: (() -> Void)? = nil

    @State private var copied = false

    private var isUser: Bool { message.role == "user" }
    private var t: (String) -> String { L10n.shared.t }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isUser ? "person.circle.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(isUser ? Color.accentColor : .purple)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? t("Vous") : t("Assistant"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !isUser, let reasoning = message.reasoning, !reasoning.isEmpty {
                    DisclosureGroup {
                        Text(reasoning)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } label: {
                        Text(t("Raisonnement"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if message.content.isEmpty && !isUser {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(t("L'assistant réfléchit…"))
                } else {
                    messageBody
                }
                if !isUser && !isStreaming && !message.content.isEmpty {
                    actions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button(action: copy) {
                Label(t("Copier"), systemImage: "doc.on.doc")
            }
            if let onRegenerate {
                Button(action: onRegenerate) {
                    Label(t("Régénérer la réponse"), systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: copy) {
                Label(copied ? t("Copié !") : t("Copier"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            if let onRegenerate {
                Button(action: onRegenerate) {
                    Label(t("Régénérer"), systemImage: "arrow.clockwise")
                }
                .help(t("Régénérer la réponse"))
            }
            if let tokenUsage = message.tokenUsage {
                Text(L10n.shared.t("%@ tokens", tokenUsage))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: message.content, options: options) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(message.content)
                .textSelection(.enabled)
        }
    }
}
