import Foundation

/// Langue de l'interface, persistée dans UserDefaults.
public enum AppLanguage: String, CaseIterable, Sendable, Codable, Identifiable {
    case fr, en
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .fr: return "Français"
        case .en: return "English"
        }
    }
}

/// Localisation maison : la clé est le texte français (fallback garanti),
/// le dictionnaire anglais fournit la traduction pour `AppLanguage.en`.
/// Le changement de langue est effectif immédiatement (les vues relisent `lang` via `t`).
public final class L10n: ObservableObject {
    public static let shared = L10n()

    private static let defaults = UserDefaults.standard
    private static let key = "appLanguage"
    private let lock = NSLock()

    @Published public var lang: AppLanguage {
        didSet { Self.defaults.set(lang.rawValue, forKey: Self.key) }
    }

    /// Instance autonome (tests) ; le singleton reste `L10n.shared`.
    public init() {
        let raw = Self.defaults.string(forKey: Self.key) ?? AppLanguage.fr.rawValue
        self.lang = AppLanguage(rawValue: raw) ?? .fr
    }

    /// Traduit `key` dans la langue courante. En français, la clé est renvoyée telle quelle.
    public func t(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        guard lang == .en else { return key }
        return Self.en[key] ?? key
    }

    /// Traduit puis formate avec les arguments (String(format:), « %@ » recommandé).
    public func t(_ key: String, _ args: CVarArg...) -> String {
        let format = t(key)
        guard !args.isEmpty else { return format }
        return String(format: format, arguments: args)
    }

    // MARK: - Dictionnaire anglais (clé = texte français)

    private static let en: [String: String] = [
        // MARK: ContentView
        "Conversations": "Conversations",
        "Nouvelle conversation": "New conversation",
        "Modèles disponibles sur le serveur": "Models available on the server",
        "Gérer le proxy LiteLLM local (installation, démarrage, configuration)": "Manage the local LiteLLM proxy (install, start, configure)",
        "Réglages": "Settings",
        "Aucune conversation": "No conversation",
        "Créez une conversation pour discuter avec vos modèles LiteLLM.": "Create a conversation to chat with your LiteLLM models.",

        // MARK: ChatView
        "Modèle": "Model",
        "Par défaut": "Default",
        "Paramètres de génération": "Generation settings",
        "Actualiser la liste des modèles depuis le serveur": "Refresh the model list from the server",
        "Température": "Temperature",
        "Tokens max : %@": "Max tokens: %@",
        "Invite système (optionnel)": "System prompt (optional)",
        "Génération": "Generation",
        "Arrêter la génération": "Stop generating",
        "Envoyer (⌘↩)": "Send (⌘↩)",
        "Erreur": "Error",
        "Impossible de récupérer les modèles : %@": "Could not fetch the models: %@",
        "Aucun modèle sélectionné. Choisissez-en un dans la barre d'outils ou définissez-en un par défaut dans les réglages.": "No model selected. Pick one in the toolbar or set a default in Settings.",
        "URL du serveur invalide — vérifiez les réglages.": "Invalid server URL — check Settings.",
        "\n\n— *Erreur : %@*": "\n\n— *Error: %@*",

        // MARK: MessageRow
        "Raisonnement": "Reasoning",
        "%@ tokens": "%@ tokens",
        "Copier": "Copy",

        // MARK: ModelsView
        "Modèles disponibles": "Available models",
        "Actualiser": "Refresh",
        "Fermer": "Close",
        "Interrogation du serveur…": "Querying the server…",
        "Aucun modèle": "No models",
        "Actualisez la liste depuis votre serveur LiteLLM.": "Refresh the list from your LiteLLM server.",
        "Utiliser par défaut": "Use as default",
        "Échec : %@": "Failed: %@",

        // MARK: SettingsView
        "Application": "Application",
        "Langue": "Language",
        "Serveur LiteLLM": "LiteLLM server",
        "URL du serveur": "Server URL",
        "Clé API": "API key",
        "Tester la connexion": "Test connection",
        "Modèles": "Models",
        "Modèle par défaut": "Default model",
        "Aucun": "None",
        "Actualiser depuis le serveur": "Refresh from server",
        "%@ modèle(s) en cache": "%@ model(s) cached",
        "URL du serveur invalide.": "Invalid server URL.",
        "Connecté — %@ modèle(s) disponible(s).": "Connected — %@ model(s) available.",
        "%@ modèle(s) — le health check a répondu hors plage 2xx.": "%@ model(s) — the health check answered outside the 2xx range.",

        // MARK: ProxyView — états
        "Proxy LiteLLM local": "Local LiteLLM proxy",
        "Non installé": "Not installed",
        "Installation en cours…": "Installing…",
        "Installé (arrêté)": "Installed (stopped)",
        "Démarrage… (premier lancement : ~10–30 s)": "Starting… (first launch: ~10–30 s)",
        "En cours (démarré hors de l'app)": "Running (started outside the app)",
        "En cours d'exécution": "Running",
        "Arrêt en cours…": "Stopping…",
        "Erreur : %@": "Error: %@",
        "health OK": "health OK",
        "Utiliser comme serveur": "Use as server",
        "Définir l'URL du serveur dans les réglages (%@)": "Set the server URL in Settings (%@)",

        // MARK: ProxyView — contrôles
        "Proxy": "Proxy",
        "Installer LiteLLM": "Install LiteLLM",
        "Démarrer": "Start",
        "Arrêter": "Stop",
        "Port : %@": "Port: %@",
        "Hôte": "Host",
        "Modifier le port ou l'hôte nécessite un redémarrage.": "Changing the port or host requires a restart.",
        "Arrêter le proxy à la fermeture de l'app": "Stop the proxy when the app quits",
        "Démarrer automatiquement au lancement": "Start automatically at launch",

        // MARK: ProxyView — master key
        "Master key": "Master key",
        "Masquer": "Hide",
        "Afficher": "Show",
        "Regénérer": "Regenerate",
        "Nouvelle master key (stockée dans le trousseau). À synchroniser dans la clé API des réglages.": "New master key (stored in the keychain). Sync it into the API key in Settings.",
        "Stockée dans le trousseau macOS et écrite dans le config.yaml généré (fichier en 0600).": "Stored in the macOS keychain and written to the generated config.yaml (file mode 0600).",

        // MARK: ProxyView — modèles (anciens champs)
        "Modèles (config.yaml)": "Models (config.yaml)",
        "Nom exposé (model_name)": "Exposed name (model_name)",
        "Modèle LiteLLM (ex. openai/gpt-4o)": "LiteLLM model (e.g. openai/gpt-4o)",
        "Clé API du fournisseur": "Provider API key",
        "API base (optionnel)": "API base (optional)",
        "Ajouter un modèle": "Add a model",
        "Ouvrir le dossier Application Support": "Open Application Support folder",
        "Les modèles sont écrits dans config.yaml au démarrage du proxy. Les changements de modèles/archive nécessitent un redémarrage du proxy.": "Models are written to config.yaml when the proxy starts. Model changes require a proxy restart.",
        "Journal d'installation": "Install log",
        "Journal du proxy": "Proxy log",
        "Ollama (local)": "Ollama (local)",
        "Personnalisé": "Custom",

        // MARK: ProxyView — nouvelles sections
        "Fournisseurs connectés": "Connected providers",
        "Aucun fournisseur pour l'instant — ajoutez votre clé API pour commencer.": "No provider yet — add your API key to get started.",
        "Ajouter un fournisseur": "Add a provider",
        "Utiliser ce proxy ailleurs": "Use this proxy elsewhere",
        "N'importe quel outil compatible OpenAI (curl, SDK Python, LangChain…) peut appeler cette URL avec cette clé : le proxy convertit automatiquement la requête dans le format de votre fournisseur.": "Any OpenAI-compatible tool (curl, Python SDK, LangChain…) can call this URL with this key: the proxy automatically converts the request to your provider's format.",
        "Base URL": "Base URL",
        "Clé API (master key)": "API key (master key)",
        "Copier la configuration complète": "Copy full configuration",
        "Copié !": "Copied!",
        "Configuration copiée dans le presse-papiers.": "Configuration copied to the clipboard.",
        "Tester": "Test",
        "Test en cours…": "Testing…",
        "Clé valide ✓": "Key valid ✓",
        "Échec du test : %@": "Test failed: %@",
        "Démarrez le proxy pour pouvoir tester": "Start the proxy to enable testing",
        "Fournisseur": "Provider",
        "Modèle du fournisseur": "Provider model",
        "Nom exposé": "Exposed name",
        "Avancé": "Advanced",
        "Modifier": "Edit",
        "Où trouver ma clé API ?": "Where do I find my API key?",
        "Coller la clé API": "Paste the API key",
        "Détecté : %@ — utiliser ce fournisseur ?": "Detected: %@ — use this provider?",
        "Personnalisé…": "Custom…",
        "Modèle personnalisé": "Custom model",
        "Charger les modèles locaux": "Load local models",
        "%@ modèle(s) détecté(s) localement": "%@ model(s) detected locally",
        "Modèles suggérés": "Suggested models",
        "Champ obligatoire": "Required field",
        "Ce fournisseur n'a pas besoin de clé API.": "This provider does not need an API key.",

        // MARK: Onboarding
        "Bienvenue dans LiteLLM-App": "Welcome to LiteLLM-App",
        "Cette application peut :": "This app can:",
        "Discuter avec l'IA directement dans cette app": "Chat with AI right inside this app",
        "Brancher vos outils existants sur n'importe quel fournisseur (OpenAI, Anthropic, Gemini, Mistral…) : le proxy convertit automatiquement les API.": "Connect your existing tools to any provider (OpenAI, Anthropic, Gemini, Mistral…): the proxy automatically converts the APIs.",
        "Quel usage principal ?": "What's your main use?",
        "Commencer": "Get started",
        "Passer": "Skip",
        "Suivant": "Next",
        "Précédent": "Back",
        "Terminer": "Done",
        "Choisissez votre fournisseur d'IA": "Choose your AI provider",
        "Indiquez votre clé API et le modèle à utiliser": "Enter your API key and which model to use",
        "Installation et démarrage du proxy": "Installing and starting the proxy",
        "Test de votre configuration": "Testing your configuration",
        "C'est prêt !": "You're all set!",
        "Étape %@ sur %@": "Step %@ of %@",
        "Lancer l'installation (quelques minutes la première fois)": "Start the installation (a few minutes the first time)",
        "Démarrer le proxy": "Start the proxy",
        "Installation terminée, démarrage…": "Installation finished, starting…",
        "Le proxy est en cours d'exécution.": "The proxy is running.",
        "Ajoutez au moins un fournisseur pour continuer.": "Add at least one provider to continue.",
        "Envoyer un message test": "Send a test message",
        "Réessayer": "Retry",
        "Réponse reçue : %@": "Response received: %@",
        "Copier la configuration pour mes autres outils": "Copy the configuration for my other tools",
        "Utiliser dans cette app": "Use in this app",
        "Ouvrir le chat": "Open chat",
        "Le test a réussi : votre clé et votre modèle fonctionnent.": "The test succeeded: your key and model work.",
        "Vérifiez la clé API et le modèle, puis réessayez.": "Check the API key and model, then retry.",

        // MARK: Snippet de configuration
        "Base URL :": "Base URL:",
        "Clé API  :": "API key: ",
        "Modèle   :": "Model:   ",
        "# Exemple de requête (compatible OpenAI) :": "# Sample request (OpenAI-compatible):",

        // MARK: Génériques
        "Oui": "Yes",
        "Non": "No",
        "OK": "OK",
        "Annuler": "Cancel",
        "Supprimer": "Delete",
        "Chargement…": "Loading…",
        "Invite système": "System prompt",
        "Assistant de configuration": "Setup assistant",
        "Démarrez le proxy avec le bouton ci-dessous.": "Start the proxy with the button below.",
        "Fournisseur : %@ — Modèle : %@": "Provider: %@ — Model: %@",
    ]
}
