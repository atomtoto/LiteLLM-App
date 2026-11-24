import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Formulaire d'édition d'un fournisseur (clé API + modèle), utilisé par l'assistant
/// de configuration et par le panneau proxy. Le `ProxyModel` est édité via un binding.
struct ProviderFormView: View {
    @Binding var model: ProxyModel
    /// Preset initialement suggéré (nil → détection depuis providerModel, ou « custom »).
    var initialPreset: ProviderPreset? = nil

    @State private var preset: ProviderPreset = ProviderPresets.custom
    @State private var selectedModel: String = ""   // id nu du modèle ; "" = personnalisé
    @State private var customModelText: String = ""
    @State private var detected: ProviderPreset? = nil
    @State private var ollamaModels: [String]? = nil
    @State private var loadingOllama = false
    @State private var ollamaError = ""

    private var t: (String) -> String { L10n.shared.t }
    private func tf(_ key: String, _ args: Any...) -> String { L10n.shared.t(key, arguments: args) }

    /// Modèles proposés : ceux détectés localement (Ollama) ou les modèles connus du preset.
    private var offeredModels: [KnownModel] {
        if let ollamaModels {
            return ollamaModels.map { KnownModel(id: $0) }
        }
        return preset.knownModels
    }

    /// Azure et « personnalisé » n'ont pas d'adresse par défaut : elle est obligatoire.
    private var requiresAPIBase: Bool {
        preset.id == "azure" || preset.id == "custom"
    }

    private var isValid: Bool {
        !model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !model.providerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (!preset.requiresAPIKey || !model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        Form {
            Section(t("Fournisseur")) {
                Picker(t("Fournisseur"), selection: Binding(get: { preset }, set: { applyPreset($0) })) {
                    ForEach(ProviderPresets.all) { p in
                        Label(t(p.displayName), systemImage: p.systemImage).tag(p)
                    }
                }
                .labelsHidden()

                if preset.requiresAPIKey {
                    SecureField(t("Coller la clé API"), text: $model.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.apiKey) { _, new in
                            if let p = ProviderPresets.detect(fromAPIKey: new), p.id != preset.id {
                                detected = p
                            } else {
                                detected = nil
                            }
                        }
                    if let url = preset.keyHelpURL {
                        Button(t("Où trouver ma clé API ?")) {
                            #if canImport(AppKit)
                            NSWorkspace.shared.open(url)
                            #endif
                        }
                        .buttonStyle(.link)
                    }
                } else {
                    Text(t("Ce fournisseur n'a pas besoin de clé API."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if requiresAPIBase {
                    TextField(t("Adresse du service (API base)"), text: $model.apiBase,
                              prompt: Text("https://…"))
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section(t("Modèle du fournisseur")) {
                if preset.id == "ollama" {
                    HStack {
                        Button(loadingOllama ? t("Chargement…") : t("Charger les modèles locaux")) {
                            Task { await loadOllamaModels() }
                        }
                        .disabled(loadingOllama || model.apiBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let ollamaModels {
                            Text(tf("%@ modèle(s) détecté(s) localement", ollamaModels.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !ollamaError.isEmpty {
                        Text(ollamaError).font(.caption).foregroundStyle(.red)
                    }
                }
                if !offeredModels.isEmpty {
                    Picker(t("Modèle du fournisseur"), selection: $selectedModel) {
                        ForEach(offeredModels) { m in
                            if ollamaModels == nil, m.id == offeredModels.first?.id {
                                Text(tf("%@ (recommandé)", m.label)).tag(m.id)
                            } else {
                                Text(m.label).tag(m.id)
                            }
                        }
                        Text(t("Personnalisé…")).tag("")
                    }
                    .onChange(of: selectedModel) { _, new in
                        applySelectedModel(new)
                    }
                }
                if offeredModels.isEmpty || selectedModel.isEmpty {
                    TextField(t("Modèle personnalisé"), text: $customModelText,
                              prompt: Text("ex. gpt-4o"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customModelText) { _, _ in
                            model.providerModel = preset.litellmPrefix + customModelText
                            if model.name.isEmpty { model.name = customModelText }
                        }
                }
            }

            Section {
                DisclosureGroup(t("Options avancées")) {
                    TextField(t("Nom exposé"), text: $model.name,
                              prompt: Text(t("Modèle du fournisseur")))
                        .textFieldStyle(.roundedBorder)
                    Text(t("Nom sous lequel ce modèle apparaît dans l'app et pour les autres outils."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !requiresAPIBase {
                        TextField(t("API base (optionnel)"), text: $model.apiBase)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { bootstrap() }
        .task(id: preset.id) {
            // Ollama : propose directement les modèles réellement installés sur le Mac.
            if preset.id == "ollama", ollamaModels == nil {
                await loadOllamaModels()
            }
        }
        .alert(
            detected.map { tf("Détecté : %@ — utiliser ce fournisseur ?", $0.displayName) } ?? "",
            isPresented: Binding(get: { detected != nil }, set: { if !$0 { detected = nil } })
        ) {
            Button(t("Oui")) {
                if let d = detected { applyPreset(d) }
                detected = nil
            }
            Button(t("Non"), role: .cancel) { detected = nil }
        }
    }

    // MARK: - Logique

    private func bootstrap() {
        let p = initialPreset ?? ProviderPresets.preset(forProviderModel: model.providerModel)
        preset = p
        let bare = ProviderPresets.bareModelID(from: model.providerModel)
        customModelText = bare
        selectedModel = p.knownModels.contains(where: { $0.id == bare }) ? bare : ""
        if !p.defaultAPIBase.isEmpty && model.apiBase.isEmpty {
            model.apiBase = p.defaultAPIBase
        }
    }

    private func applyPreset(_ p: ProviderPreset) {
        preset = p
        let bare = ProviderPresets.bareModelID(from: model.providerModel)
        let modelID: String
        if p.knownModels.contains(where: { $0.id == bare }) {
            modelID = bare
        } else {
            modelID = p.knownModels.first?.id ?? bare
        }
        model.providerModel = p.litellmPrefix + modelID
        if !p.defaultAPIBase.isEmpty && model.apiBase.isEmpty {
            model.apiBase = p.defaultAPIBase
        }
        selectedModel = p.knownModels.contains(where: { $0.id == modelID }) ? modelID : ""
        customModelText = modelID
        if model.name.isEmpty { model.name = modelID }
        ollamaModels = nil
        ollamaError = ""
    }

    private func applySelectedModel(_ new: String) {
        if new.isEmpty {
            model.providerModel = preset.litellmPrefix + customModelText
            if model.name.isEmpty { model.name = customModelText }
        } else {
            model.providerModel = preset.litellmPrefix + new
            if model.name.isEmpty { model.name = new }
        }
    }

    private func loadOllamaModels() async {
        loadingOllama = true
        ollamaError = ""
        defer { loadingOllama = false }
        do {
            let models = try await OllamaCatalog.fetchModels(apiBase: model.apiBase)
            ollamaModels = models
            if models.isEmpty {
                ollamaError = t("Ollama ne contient encore aucun modèle. Installez-en un depuis l'app Ollama (ex. llama3.3).")
            } else if !models.contains(selectedModel), let first = models.first {
                selectedModel = first
            }
        } catch {
            ollamaError = t("Ollama ne répond pas. Vérifiez qu'Ollama est installé et ouvert (ollama.com).")
        }
    }
}
