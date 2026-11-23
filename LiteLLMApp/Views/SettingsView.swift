import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var testing = false
    @State private var testMessage = ""
    @State private var testOK = false

    var body: some View {
        Form {
            Section("Serveur LiteLLM") {
                TextField("URL du serveur", text: $settings.serverURL,
                          prompt: Text("http://localhost:4000"))
                    .textFieldStyle(.roundedBorder)
                SecureField("Clé API", text: $settings.apiKey, prompt: Text("sk-…"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settings.apiKey) { _, _ in
                        settings.saveAPIKeyToKeychain()
                    }
                HStack {
                    Button("Tester la connexion") { Task { await testConnection() } }
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

            Section("Modèles") {
                Picker("Modèle par défaut", selection: $settings.defaultModel) {
                    Text("Aucun").tag("")
                    ForEach(settings.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Button("Actualiser depuis le serveur") { Task { await refreshModels() } }
                    .disabled(settings.baseURL == nil)
                if !settings.availableModels.isEmpty {
                    Text("\(settings.availableModels.count) modèle(s) en cache")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Génération") {
                HStack {
                    Text("Température")
                    Slider(value: $settings.temperature, in: 0...2, step: 0.05)
                    Text(settings.temperature, format: .number.precision(.fractionLength(2)))
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $settings.maxTokens, in: 16...200_000, step: 256) {
                    Text("Tokens max : \(settings.maxTokens)")
                }
                TextField("Invite système (optionnel)", text: $settings.systemPrompt, axis: .vertical)
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
            testMessage = "URL du serveur invalide."
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
                ? "Connecté — \(models.count) modèle(s) disponible(s)."
                : "\(models.count) modèle(s) — le health check a répondu hors plage 2xx."
        } catch {
            testOK = false
            testMessage = "Échec : \(error.localizedDescription)"
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
            testMessage = "Échec : \(error.localizedDescription)"
        }
    }
}
