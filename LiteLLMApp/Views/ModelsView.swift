import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var models: [ModelInfo] = []
    @State private var loading = false
    @State private var message = ""

    private var t: (String) -> String { L10n.shared.t }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("Modèles disponibles")).font(.headline)
                Spacer()
                Button(t("Actualiser")) { Task { await load() } }
                Button(t("Fermer")) { dismiss() }
            }
            .padding()
            Divider()
            if loading && models.isEmpty {
                ProgressView(t("Interrogation du serveur…"))
                    .padding()
            } else if models.isEmpty {
                ContentUnavailableView {
                    Label(t("Aucun modèle"), systemImage: "server.rack")
                } description: {
                    Text(message.isEmpty ? t("Actualisez la liste depuis votre serveur LiteLLM.") : message)
                }
            } else {
                List(models) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.id)
                            if let owner = model.ownedBy {
                                Text(owner)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if settings.defaultModel == model.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Button(t("Utiliser par défaut")) {
                            settings.defaultModel = model.id
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if !message.isEmpty && !models.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 520, minHeight: 380)
        .task { await load() }
    }

    private func load() async {
        loading = true
        message = ""
        defer { loading = false }
        guard let client = settings.makeClient() else {
            message = t("URL du serveur invalide — vérifiez les réglages.")
            return
        }
        do {
            models = try await client.listModels()
            settings.availableModels = models.map(\.id).sorted()
        } catch {
            message = L10n.shared.t("Échec : %@", error.localizedDescription)
        }
    }
}
