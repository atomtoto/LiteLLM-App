import SwiftUI

/// Fenêtre « Utiliser avec d'autres apps » : génère la commande qui branche Codex, Claude Code
/// ou tout autre outil sur le service local, avec n'importe quel fournisseur configuré
/// (ex. Codex avec une clé Anthropic, Claude Code avec une clé Mistral).
struct ExternalToolsView: View {
    @EnvironmentObject private var proxy: ProxyManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("externalTool") private var tool: ExternalTool = .codex
    @AppStorage("externalToolModel") private var model = ""
    @State private var copied = false
    @State private var launchError: String?
    /// Contenu actuel de `~/.codex/config.toml` (outil « App Codex »).
    @State private var codexToml = ""
    @State private var isApplying = false

    private var t: (String) -> String { L10n.shared.t }
    private func tf(_ key: String, _ args: Any...) -> String { L10n.shared.t(key, arguments: args) }

    private var baseURL: String { proxy.baseURL?.absoluteString ?? "" }

    private var validModels: [ProxyModel] {
        proxy.settings.models.filter { !$0.name.isEmpty && !$0.providerModel.isEmpty }
    }

    private var command: String {
        ShareConfig.command(for: tool, baseURL: baseURL, apiKey: proxy.masterKey(), model: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                if validModels.isEmpty {
                    ContentUnavailableView(
                        t("Aucun fournisseur"),
                        systemImage: "key",
                        description: Text(t("Ajoutez d'abord une clé API dans « Fournisseurs d'IA »."))
                    )
                } else {
                    if !proxy.isRunning {
                        notRunningSection
                    }
                    toolSection
                    if tool == .codexApp {
                        codexAppSection
                    } else {
                        commandSection
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(t("Utiliser avec d'autres apps"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Terminé")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 440, idealHeight: 520)
        .onAppear {
            ensureValidModel()
            codexToml = CodexAppConfig.read()
        }
        .onChange(of: proxy.settings.models.count) { _, _ in ensureValidModel() }
        .onChange(of: tool) { _, _ in copied = false; codexToml = CodexAppConfig.read() }
        .onChange(of: model) { _, _ in copied = false }
        .alert(t("Une erreur est survenue"), isPresented: Binding(
            get: { launchError != nil }, set: { if !$0 { launchError = nil } }
        )) {
            Button(t("OK")) { launchError = nil }
        } message: {
            Text(launchError ?? "")
        }
    }

    // MARK: - Sections

    private var notRunningSection: some View {
        Section {
            LabeledContent {
                Button(t("Démarrer")) { proxy.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(proxy.isBusy || !proxy.isInstalled)
            } label: {
                Text(t("Le service IA est arrêté."))
                Text(t("Il doit tourner pour que les autres apps puissent l'utiliser."))
            }
        }
    }

    private var toolSection: some View {
        Section {
            Picker(t("Outil"), selection: $tool) {
                ForEach(ExternalTool.allCases) { tool in
                    Text(title(of: tool)).tag(tool)
                }
            }
            Picker(t("Modèle"), selection: $model) {
                ForEach(validModels) { m in
                    Text(m.name).tag(m.name)
                }
            }
        } footer: {
            Text(explanation(of: tool))
                .foregroundStyle(.secondary)
        }
    }

    private var commandSection: some View {
        Section {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                if tool.executable != nil {
                    Button(t("Ouvrir dans le Terminal"), systemImage: "terminal", action: launch)
                        .buttonStyle(.borderedProminent)
                        .disabled(!proxy.isRunning)
                }
                Button(t("Copier"), systemImage: "doc.on.doc") {
                    ShareConfig.copyValue(command)
                    copied = true
                }
                if copied {
                    Label(t("Copié !"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text(tool.executable != nil ? t("Commande à lancer") : t("Variables à définir"))
        } footer: {
            if proxy.settings.stopOnQuit {
                Text(t("Gardez LiteLLM-App ouverte pendant l'utilisation : le service s'arrête quand l'app se ferme (modifiable dans « Fournisseurs d'IA » ▸ Options)."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codexAppSection: some View {
        let enabled = CodexAppConfig.isEnabled(codexToml)
        let upToDate = codexToml == CodexAppConfig.enable(in: codexToml, baseURL: baseURL, apiKey: proxy.masterKey(),
                                                          model: model, catalogPath: CodexAppConfig.catalogURL.path)
            && CodexAppConfig.catalogModels() == [model] + validModels.map(\.name).filter { $0 != model }
        return Section {
            LabeledContent {
                HStack {
                    if isApplying {
                        ProgressView().controlSize(.small)
                    }
                    if !upToDate {
                        Button(enabled ? t("Mettre à jour") : t("Activer")) { Task { await applyCodexApp(enable: true) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(isApplying)
                    }
                    if enabled {
                        Button(t("Désactiver")) { Task { await applyCodexApp(enable: false) } }
                            .disabled(isApplying)
                    }
                }
            } label: {
                if enabled {
                    Label(tf("Activé avec « %@ »", CodexAppConfig.enabledModel(codexToml) ?? model),
                          systemImage: "checkmark.circle.fill")
                    Text(upToDate
                         ? t("Quittez puis rouvrez l'app Codex pour appliquer le changement.")
                         : t("Le modèle ou la clé du service a changé : mettez à jour la configuration."))
                } else {
                    Label(t("Désactivé"), systemImage: "circle")
                    Text(t("L'app Codex utilise ses modèles OpenAI habituels."))
                }
            }
        } header: {
            Text(t("App Codex"))
        } footer: {
            Text(t("Modifie ~/.codex/config.toml (une sauvegarde est créée à côté) ; le CLI codex est aussi concerné. Tant que c'est activé, LiteLLM-App doit rester ouverte. « Désactiver » restaure vos réglages d'origine."))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Textes

    private func title(of tool: ExternalTool) -> String {
        switch tool {
        case .codex: return "Codex CLI"
        case .codexApp: return t("App Codex (ChatGPT)")
        case .claudeCode: return "Claude Code"
        case .openAICompatible: return t("Autre outil (format OpenAI)")
        case .anthropicCompatible: return t("Autre outil (format Anthropic)")
        }
    }

    private func explanation(of tool: ExternalTool) -> String {
        switch tool {
        case .codex:
            return t("Codex utilisera le modèle choisi (Claude, Mistral, Gemini…) au lieu des modèles OpenAI. Votre configuration Codex n'est pas modifiée.")
        case .codexApp:
            return t("L'app Codex pour Mac utilisera le modèle choisi (Claude, Mistral, Gemini…) au lieu des modèles OpenAI, jusqu'à ce que vous désactiviez l'option.")
        case .claudeCode:
            return t("Claude Code utilisera le modèle choisi (GPT, Mistral, Gemini…) à la place de Claude. Votre compte Claude n'est pas modifié.")
        case .openAICompatible:
            return t("Pour les outils et SDK compatibles OpenAI (Aider, LangChain, SDK Python…) : définissez ces variables, puis indiquez le nom du modèle.")
        case .anthropicCompatible:
            return t("Pour les outils et SDK compatibles Anthropic : définissez ces variables, puis indiquez le nom du modèle.")
        }
    }

    // MARK: - Actions

    private func ensureValidModel() {
        if !validModels.contains(where: { $0.name == model }) {
            model = validModels.first?.name ?? ""
        }
    }

    private func applyCodexApp(enable: Bool) async {
        isApplying = true
        defer { isApplying = false }
        let current = CodexAppConfig.read()
        do {
            if enable {
                // Catalogue : le sélecteur de Codex propose les modèles du proxy, en mode outils classique.
                let template = await CodexAppConfig.fetchTemplate()
                let catalog = try CodexAppConfig.catalog(models: validModels.map(\.name), defaultModel: model,
                                                         template: template)
                try catalog.write(to: CodexAppConfig.catalogURL, options: .atomic)
                try CodexAppConfig.write(CodexAppConfig.enable(in: current, baseURL: baseURL, apiKey: proxy.masterKey(),
                                                               model: model, catalogPath: CodexAppConfig.catalogURL.path))
            } else {
                try CodexAppConfig.write(CodexAppConfig.disable(in: current))
                try? FileManager.default.removeItem(at: CodexAppConfig.catalogURL)
            }
        } catch {
            launchError = error.localizedDescription
        }
        codexToml = CodexAppConfig.read()
    }

    private func launch() {
        do {
            try ShareConfig.launchInTerminal(tool, baseURL: baseURL, apiKey: proxy.masterKey(), model: model)
        } catch {
            launchError = error.localizedDescription
        }
    }
}
