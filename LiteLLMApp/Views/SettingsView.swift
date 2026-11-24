import SwiftUI

struct SettingsView: View {
    private var t: (String) -> String { L10n.shared.t }

    var body: some View {
        TabView {
            Tab(t("Général"), systemImage: "gear") {
                GeneralSettingsTab()
            }
            Tab(t("Réponses"), systemImage: "text.bubble") {
                GenerationSettingsForm()
            }
            Tab(t("Connexion"), systemImage: "network") {
                ConnectionSettingsTab()
            }
        }
        .frame(width: 540, height: 440)
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    private var t: (String) -> String { L10n.shared.t }

    var body: some View {
        Form {
            Picker(t("Langue"), selection: Binding(
                get: { L10n.shared.lang },
                set: { L10n.shared.lang = $0 }
            )) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            Section {
                Picker(t("Modèle par défaut"), selection: $settings.defaultModel) {
                    Text(t("Aucun")).tag("")
                    if !settings.defaultModel.isEmpty && !settings.availableModels.contains(settings.defaultModel) {
                        Text(settings.defaultModel).tag(settings.defaultModel)
                    }
                    ForEach(settings.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            } footer: {
                Text(t("Utilisé pour les nouvelles conversations. Vous pouvez en changer à tout moment dans la barre d'outils du chat."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await settings.refreshAvailableModels() }
    }
}

private struct ConnectionSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var proxy: ProxyManager
    @State private var testing = false
    @State private var testMessage = ""
    @State private var testOK = false

    private var t: (String) -> String { L10n.shared.t }

    var body: some View {
        Form {
            Section {
                if settings.isConnected(to: proxy.baseURL) {
                    Label(t("L'app utilise le service IA local géré par l'app (recommandé)."), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let url = proxy.baseURL, proxy.isInstalled {
                    LabeledContent {
                        Button(t("Utiliser le service local")) {
                            settings.connect(toProxyAt: url, masterKey: proxy.masterKey())
                        }
                    } label: {
                        Text(t("L'app utilise un serveur externe."))
                    }
                }
            } footer: {
                Text(t("Ne modifiez ces réglages que si vous utilisez votre propre serveur LiteLLM."))
                    .foregroundStyle(.secondary)
            }

            Section(t("Serveur LiteLLM")) {
                TextField(t("URL du serveur"), text: $settings.serverURL,
                          prompt: Text("http://localhost:4000"))
                SecureField(t("Clé API"), text: $settings.apiKey, prompt: Text("sk-…"))
                    .onChange(of: settings.apiKey) { _, _ in
                        settings.saveAPIKeyToKeychain()
                    }
                LabeledContent {
                    HStack {
                        if testing {
                            ProgressView().controlSize(.small)
                        }
                        Button(t("Tester la connexion")) { Task { await testConnection() } }
                            .disabled(testing || settings.baseURL == nil)
                    }
                } label: {
                    if !testMessage.isEmpty {
                        Label(testMessage,
                              systemImage: testOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(testOK ? .green : .red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
            let models = try await client.listModels()
            settings.availableModels = models.map(\.id).sorted()
            if settings.defaultModel.isEmpty {
                settings.defaultModel = settings.availableModels.first ?? ""
            }
            testOK = true
            testMessage = L10n.shared.t("Connecté — %@ modèle(s) disponible(s).", models.count)
        } catch {
            testOK = false
            testMessage = FriendlyError.message(for: error)
        }
    }
}
