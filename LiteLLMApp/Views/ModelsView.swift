import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var models: [ModelInfo] = []
    @State private var loading = false
    @State private var message = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Modèles disponibles").font(.headline)
                Spacer()
                Button("Actualiser") { Task { await load() } }
                Button("Fermer") { dismiss() }
            }
            .padding()
            Divider()
            if loading && models.isEmpty {
                ProgressView("Interrogation du serveur…")
                    .padding()
            } else if models.isEmpty {
                ContentUnavailableView {
                    Label("Aucun modèle", systemImage: "server.rack")
                } description: {
                    Text(message.isEmpty ? "Actualisez la liste depuis votre serveur LiteLLM." : message)
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
                        Button("Utiliser par défaut") {
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
            message = "URL du serveur invalide — vérifiez les réglages."
            return
        }
        do {
            models = try await client.listModels()
            settings.availableModels = models.map(\.id).sorted()
        } catch {
            message = "Échec : \(error.localizedDescription)"
        }
    }
}
