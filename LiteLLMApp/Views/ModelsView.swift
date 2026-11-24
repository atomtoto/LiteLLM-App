import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var models: [ModelInfo] = []
    @State private var loading = false
    @State private var message = ""

    private var t: (String) -> String { L10n.shared.t }

    var body: some View {
        NavigationStack {
            Group {
                if loading && models.isEmpty {
                    ProgressView(t("Interrogation du serveur…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if models.isEmpty {
                    ContentUnavailableView {
                        Label(t("Aucun modèle"), systemImage: "server.rack")
                    } description: {
                        Text(message.isEmpty ? t("Ajoutez un fournisseur dans « Fournisseurs d'IA », puis actualisez.") : message)
                    } actions: {
                        Button(t("Réessayer")) { Task { await load() } }
                    }
                } else {
                    List(models) { model in
                        LabeledContent {
                            if settings.defaultModel == model.id {
                                Label(t("Par défaut"), systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Button(t("Utiliser par défaut")) {
                                    settings.defaultModel = model.id
                                }
                            }
                        } label: {
                            Text(model.id)
                            if let owner = model.ownedBy {
                                Text(owner)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(t("Modèles disponibles"))
            .toolbar {
                ToolbarItem {
                    Button { Task { await load() } } label: {
                        Label(t("Actualiser"), systemImage: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Terminé")) { dismiss() }
                }
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
            models = []
            message = FriendlyError.message(for: error)
        }
    }
}
