import SwiftUI

/// Carte lisible d'un fournisseur connecté au proxy : presets, clé, test, édition.
struct ProviderCardView: View {
    @Binding var model: ProxyModel
    @EnvironmentObject private var proxy: ProxyManager
    @State private var editing = false
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, testing, ok, failed(String)
    }

    private var t: (String) -> String { L10n.shared.t }
    private func tf(_ key: String, _ args: CVarArg...) -> String { L10n.shared.t(key, args) }

    private var preset: ProviderPreset {
        ProviderPresets.preset(forProviderModel: model.providerModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: preset.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(preset.displayName)).font(.headline)
                    Text(model.providerModel)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                testBadge
                Button {
                    Task { await runTest() }
                } label: {
                    if case .testing = testState {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(t("Tester"), systemImage: "play.circle")
                    }
                }
                .disabled(!proxy.isRunning || isTesting)
                .help(proxy.isRunning ? t("Tester") : t("Démarrez le proxy pour pouvoir tester"))
                Button(t("Modifier")) { editing = true }
                Button(role: .destructive) {
                    proxy.settings.models.removeAll { $0.id == model.id }
                    proxy.saveSettings()
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)
                .help(t("Supprimer"))
            }

            HStack {
                if preset.requiresAPIKey {
                    SecureField(t("Clé API du fournisseur"), text: $model.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.apiKey) { _, _ in proxy.saveSettings() }
                } else {
                    Text(t("Ce fournisseur n'a pas besoin de clé API."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.apiBase.isEmpty {
                Text(model.apiBase)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            if !model.name.isEmpty {
                Text(tf("Nom exposé : %@", model.name))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $editing) {
            VStack(spacing: 0) {
                ProviderFormView(model: $model, initialPreset: preset)
                    .padding()
                Divider()
                HStack {
                    Spacer()
                    Button(t("Fermer")) { editing = false }
                        .keyboardShortcut(.return)
                }
                .padding()
            }
            .frame(minWidth: 560, minHeight: 480)
            .onDisappear { proxy.saveSettings() }
        }
    }

    private var isTesting: Bool {
        if case .testing = testState { return true }
        return false
    }

    @ViewBuilder
    private var testBadge: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            EmptyView()
        case .ok:
            Label(t("Clé valide ✓"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let message):
            Label(tf("Échec du test : %@", message), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(1)
        }
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
            testState = .failed(error.localizedDescription)
        }
    }
}
