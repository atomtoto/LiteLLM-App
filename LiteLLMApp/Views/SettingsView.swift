import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var testing = false
    @State private var testMessage = ""
    @State private var testOK = false

    private var t: (String) -> String { L10n.shared.t }

    var body: some View {
        Form {
            Section(t("Application")) {
                Picker(t("Langue"), selection: Binding(
                    get: { L10n.shared.lang },
                    set: { L10n.shared.lang = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section(t("Serveur LiteLLM")) {
                TextField(t("URL du serveur"), text: $settings.serverURL,
                          prompt: Text("http://localhost:4000"))
                    .textFieldStyle(.roundedBorder)
                SecureField(t("Clé API"), text: $settings.apiKey, prompt: Text("sk-…"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settings.apiKey) { _, _ in
                        settings.saveAPIKeyToKeychain()
                    }
                HStack {
                    Button(t("Tester la connexion")) { Task { await testConnection() } }
                        .disabled(testing || settings.baseURL == nil)
                    if testing {
                        ProgressView().controlSize(.small)
                    }
                }
                if !testMessage.isEmpty {
                    Label(testMessage,
                          systemImage: testOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(testOK ? .green : .red)
                        .font(.callout)
                }
            }

            Section(t("Modèles")) {
                Picker(t("Modèle par défaut"), selection: $settings.defaultModel) {
                    Text(t("Aucun")).tag("")
                    ForEach(settings.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Button(t("Actualiser depuis le serveur")) { Task { await refreshModels() } }
                    .disabled(settings.baseURL == nil)
                if !settings.availableModels.isEmpty {
                    Text(L10n.shared.t("%@ modèle(s) en cache", settings.availableModels.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(t("Génération")) {
                HStack {
                    Text(t("Température"))
                    Slider(value: $settings.temperature, in: 0...2, step: 0.05)
                    Text(settings.temperature, format: .number.precision(.fractionLength(2)))
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $settings.maxTokens, in: 16...200_000, step: 256) {
                    Text(L10n.shared.t("Tokens max : %@", settings.maxTokens))
                }
                TextField(t("Invite système (optionnel)"), text: $settings.systemPrompt, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 420)
    }

    private func testConnection() async {
        testing = true
        testMessage = ""
        defer { testing = false }
        guard let client = settings.makeClient() else {
            testOK = false
            testMessage = t("URL du serveur invalide.")
            return
        }
        do {
            let healthy = try await client.health()
            let models = try await client.listModels()
            settings.availableModels = models.map(\.id).sorted()
            if settings.defaultModel.isEmpty {
                settings.defaultModel = settings.availableModels.first ?? ""
            }
            testOK = true
            testMessage = healthy
                ? L10n.shared.t("Connecté — %@ modèle(s) disponible(s).", models.count)
                : L10n.shared.t("%@ modèle(s) — le health check a répondu hors plage 2xx.", models.count)
        } catch {
            testOK = false
            testMessage = L10n.shared.t("Échec : %@", error.localizedDescription)
        }
    }

    private func refreshModels() async {
        guard let client = settings.makeClient() else { return }
        do {
            let models = try await client.listModels()
            settings.availableModels = models.map(\.id).sorted()
            if settings.defaultModel.isEmpty {
                settings.defaultModel = settings.availableModels.first ?? ""
            }
        } catch {
            testOK = false
            testMessage = L10n.shared.t("Échec : %@", error.localizedDescription)
        }
    }
}
