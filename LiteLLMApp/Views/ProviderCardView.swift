import SwiftUI

/// Ligne d'un fournisseur connecté au proxy : nom, modèle, test en un clic, édition, suppression.
struct ProviderCardView: View {
    @Binding var model: ProxyModel
    @EnvironmentObject private var proxy: ProxyManager
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, testing, ok, failed(String)
    }

    private var t: (String) -> String { L10n.shared.t }
    private func tf(_ key: String, _ args: Any...) -> String { L10n.shared.t(key, arguments: args) }

    private var preset: ProviderPreset {
        ProviderPresets.preset(forProviderModel: model.providerModel)
    }

    /// Fin de la clé (« ••••1234 ») pour reconnaître la clé sans l'afficher.
    private var maskedKey: String {
        let key = model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count > 8 else { return key.isEmpty ? "" : "••••" }
        return "••••" + key.suffix(4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: preset.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name.isEmpty ? t(preset.displayName) : model.name)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await runTest() }
                } label: {
                    if testState == .testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(t("Tester"))
                    }
                }
                .disabled(!proxy.isRunning || testState == .testing || proxy.needsRestart)
                .help(proxy.isRunning ? t("Envoie un court message pour vérifier la clé et le modèle")
                                      : t("Démarrez le proxy pour pouvoir tester"))
                Menu {
                    Button(t("Modifier…"), systemImage: "pencil") { editing = true }
                    Button(t("Supprimer…"), systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Label(t("Actions"), systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            testResult
        }
        .padding(.vertical, 2)
        .onChange(of: model) { _, _ in testState = .idle }
        .sheet(isPresented: $editing, onDismiss: applyChanges) {
            NavigationStack {
                ProviderFormView(model: $model, initialPreset: preset)
                    .navigationTitle(t("Modifier le fournisseur"))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(t("Terminé")) { editing = false }
                        }
                    }
            }
            .frame(minWidth: 560, minHeight: 480)
        }
        .confirmationDialog(tf("Supprimer « %@ » ?", model.name), isPresented: $confirmDelete) {
            Button(t("Supprimer"), role: .destructive) { delete() }
        } message: {
            Text(t("Ce modèle ne sera plus disponible dans l'app ni pour vos autres outils."))
        }
    }

    private var subtitle: String {
        var parts = [t(preset.displayName), model.providerModel]
        if preset.requiresAPIKey {
            parts.append(maskedKey.isEmpty ? t("clé API manquante") : tf("clé %@", maskedKey))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var testResult: some View {
        switch testState {
        case .idle, .testing:
            EmptyView()
        case .ok:
            Label(t("Fonctionne correctement"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func applyChanges() {
        proxy.saveSettings()
        if proxy.needsRestart { proxy.restart() }
    }

    private func delete() {
        // Capturer l'id avant : lire le binding pendant la mutation du tableau serait un accès concurrent.
        let id = model.id
        proxy.settings.models.removeAll { $0.id == id }
        proxy.saveSettings()
        if proxy.needsRestart { proxy.restart() }
    }

    private func runTest() async {
        guard let url = proxy.baseURL else { return }
        testState = .testing
        let client = LiteLLMClient(baseURL: url, apiKey: proxy.masterKey())
        let target = model.name.isEmpty ? model.providerModel : model.name
        do {
            _ = try await client.testChatCompletion(model: target)
            testState = .ok
        } catch {
            testState = .failed(FriendlyError.message(for: error))
        }
    }
}
