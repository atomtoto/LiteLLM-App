import Foundation
import Observation

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
/// `@Observable` : toute vue qui appelle `t(...)` dans son `body` lit `lang`
/// et se redessine donc immédiatement au changement de langue.
@Observable
public final class L10n {
    public static let shared = L10n()

    private static let defaults = UserDefaults.standard
    private static let key = "appLanguage"

    public var lang: AppLanguage {
        didSet { Self.defaults.set(lang.rawValue, forKey: Self.key) }
    }

    /// Instance autonome (tests) ; le singleton reste `L10n.shared`.
    /// Sans choix enregistré, suit la langue du système (français sinon anglais).
    public init() {
        if let raw = Self.defaults.string(forKey: Self.key), let saved = AppLanguage(rawValue: raw) {
            self.lang = saved
        } else {
            let system = Locale.preferredLanguages.first ?? "fr"
            self.lang = system.hasPrefix("fr") ? .fr : .en
        }
    }

    /// Traduit `key` dans la langue courante. En français, la clé est renvoyée telle quelle.
    public func t(_ key: String) -> String {
        guard lang == .en else { return key }
        return Self.en[key] ?? key
    }

    /// Traduit puis remplace chaque « %@ » par l'argument suivant (n'importe quel type).
    public func t(_ key: String, _ args: Any...) -> String {
        t(key, arguments: args)
    }

    /// Variante tableau, pour relayer des arguments variadiques.
    /// Le remplacement est fait à la main (et non via `String(format:)`) pour ne jamais
    /// planter quand un `Int` est passé à « %@ ».
    public func t(_ key: String, arguments: [Any]) -> String {
        Self.format(t(key), arguments)
    }

    static func format(_ format: String, _ args: [Any]) -> String {
        guard !args.isEmpty else { return format }
        var result = ""
        var remaining = args[...]
        var rest = format[...]
        while let range = rest.range(of: "%@") {
            result += rest[..<range.lowerBound]
            if let next = remaining.popFirst() {
                result += String(describing: next)
            } else {
                result += "%@"
            }
            rest = rest[range.upperBound...]
        }
        return result + rest
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

        // MARK: Refonte UX (débutants)
        "%@ (recommandé)": "%@ (recommended)",
        "Actions": "Actions",
        "Adresse du service (API base)": "Service address (API base)",
        "Aide-moi à rédiger un e-mail poli pour décliner une invitation.": "Help me write a polite email declining an invitation.",
        "Ajouter": "Add",
        "Ajoutez un fournisseur dans « Fournisseurs d'IA », puis actualisez.": "Add a provider in “AI Providers”, then refresh.",
        "Arrêter la génération (Échap)": "Stop generating (Esc)",
        "Arrêté": "Stopped",
        "Assistant": "Assistant",
        "Assistant de configuration…": "Setup Assistant…",
        "Aucune conversation sélectionnée": "No conversation selected",
        "Autre service compatible OpenAI": "Another OpenAI-compatible service",
        "Base URL : %@": "Base URL: %@",
        "Bienvenue !": "Welcome!",
        "Branchez le chat sur ce service pour discuter avec vos fournisseurs.": "Connect the chat to this service to talk with your providers.",
        "Ce modèle est introuvable. Choisissez un autre modèle dans la liste.": "This model could not be found. Choose another model from the list.",
        "Ce modèle ne sera plus disponible dans l'app ni pour vos autres outils.": "This model will no longer be available in the app or your other tools.",
        "Ces instructions sont envoyées au modèle au début de chaque conversation.": "These instructions are sent to the model at the start of every conversation.",
        "Cette action est définitive.": "This cannot be undone.",
        "Choisissez d'abord un modèle dans la barre d'outils.": "First choose a model in the toolbar.",
        "Choisissez un modèle pour continuer.": "Choose a model to continue.",
        "Sinon, cliquez sur le service dont vous avez (ou voulez créer) une clé API.": "Otherwise, click the service you have (or want to create) an API key for.",
        "Collez votre clé API pour continuer.": "Paste your API key to continue.",
        "Commencer à discuter": "Start chatting",
        "Configuration": "Configuration",
        "Configurer": "Set up",
        "Configurer maintenant": "Set up now",
        "Connecter l'app": "Connect the app",
        "Connexion": "Connection",
        "Continuer quand même": "Continue anyway",
        "Copier la configuration": "Copy configuration",
        "Créatif": "Creative",
        "Création de l'environnement Python avec %@…": "Creating the Python environment with %@…",
        "Créativité": "Creativity",
        "Créez une conversation pour discuter avec l'IA.": "Create a conversation to chat with the AI.",
        "Donne-moi 5 idées de repas rapides pour la semaine.": "Give me 5 quick meal ideas for the week.",
        "Démarrage du service IA…": "Starting the AI service…",
        "Démarrer le service IA": "Start the AI service",
        "Détail : %@": "Details: %@",
        "Détails techniques": "Technical details",
        "ERREUR : %@": "ERROR: %@",
        "En attente": "Waiting",
        "En cours": "In progress",
        "Envoi d'un message de test à l'IA…": "Sending a test message to the AI…",
        "Envoie un court message pour vérifier la clé et le modèle": "Sends a short message to check the key and model",
        "Envoyer": "Send",
        "Envoyer (Entrée) — ⌥Entrée pour aller à la ligne": "Send (Return) — ⌥Return for a new line",
        "Erreur HTTP %@ : %@": "HTTP error %@: %@",
        "Ex. : Réponds toujours en français, de façon concise.": "E.g.: Always answer concisely, in English.",
        "Explique-moi simplement comment fonctionne l'IA.": "Explain simply how AI works.",
        "Fermer l'assistant (vous pourrez le relancer depuis le menu IA)": "Close the assistant (you can reopen it from the AI menu)",
        "Fonctionne correctement": "Working correctly",
        "Fournisseur reconnu : %@": "Provider recognized: %@",
        "Fournisseurs d'IA": "AI Providers",
        "Fournisseurs d'IA…": "AI Providers…",
        "Gratuit, sur votre Mac, sans clé": "Free, on your Mac, no key",
        "Général": "General",
        "Gérer le service IA local : fournisseurs, clés API, démarrage": "Manage the local AI service: providers, API keys, startup",
        "IA": "AI",
        "IA européenne": "European AI",
        "Il vous faut simplement une clé API d'un fournisseur d'IA — ou Ollama, gratuit, qui fonctionne sur votre Mac sans clé. Comptez environ 5 minutes la première fois.": "All you need is an API key from an AI provider — or Ollama, which is free and runs on your Mac without a key. Allow about 5 minutes the first time.",
        "Impossible de créer l'environnement Python (pip introuvable).": "Could not create the Python environment (pip not found).",
        "Impossible de joindre le serveur. Vérifiez que le proxy est démarré (bouton « Démarrer » en haut de la fenêtre).": "Could not reach the server. Make sure the proxy is running (“Start” button at the top of the window).",
        "Installation de litellm[proxy] (cela peut prendre quelques minutes)…": "Installing litellm[proxy] (this can take a few minutes)…",
        "Installation du service IA… (quelques minutes la première fois)": "Installing the AI service… (a few minutes the first time)",
        "Installation terminée.": "Installation finished.",
        "Installer": "Install",
        "Installer le service IA (une seule fois, quelques minutes)": "Install the AI service (once, a few minutes)",
        "Installer les outils Apple": "Install Apple tools",
        "Instructions permanentes": "Custom instructions",
        "L'app est configurée et le service IA démarrera automatiquement à chaque lancement. Vous pouvez ajouter d'autres fournisseurs plus tard via le bouton « Fournisseurs d'IA ».": "The app is set up and the AI service will start automatically at every launch. You can add more providers later with the “AI Providers” button.",
        "L'app installe et démarre un petit service local qui fait le lien avec votre fournisseur. Il ne faut rien faire : patientez simplement.": "The app installs and starts a small local service that talks to your provider. There is nothing to do: just wait.",
        "L'app utilise le service IA local géré par l'app (recommandé).": "The app uses the local AI service managed by the app (recommended).",
        "L'app utilise un serveur externe.": "The app uses an external server.",
        "L'assistant réfléchit…": "The assistant is thinking…",
        "L'installation a échoué (code %@). Vérifiez votre connexion Internet, puis réessayez.": "Installation failed (code %@). Check your Internet connection, then retry.",
        "La clé API a été refusée. Vérifiez la clé de votre fournisseur dans « Fournisseurs d'IA », ou relancez l'assistant de configuration.": "The API key was rejected. Check your provider key in “AI Providers”, or run the Setup Assistant again.",
        "La requête a été refusée par le fournisseur. Vérifiez que le modèle choisi est correct.": "The provider rejected the request. Check that the chosen model is correct.",
        "Lancement impossible : %@": "Could not launch: %@",
        "Le chat de l'app utilise un autre serveur.": "The app chat uses another server.",
        "Le fournisseur a mis trop de temps à répondre. Réessayez dans un instant.": "The provider took too long to answer. Try again in a moment.",
        "Le fournisseur ou le proxy a rencontré une erreur. Réessayez dans un instant.": "The provider or the proxy ran into an error. Try again in a moment.",
        "Le serveur a renvoyé une erreur.": "The server returned an error.",
        "Le serveur ne répond pas (délai dépassé). Réessayez dans un instant.": "The server is not responding (timed out). Try again in a moment.",
        "Le service IA a rencontré un problème.": "The AI service ran into a problem.",
        "Le service IA est arrêté.": "The AI service is stopped.",
        "Le service IA n'est pas encore installé.": "The AI service is not installed yet.",
        "Le service ne répond pas après 120 s. Consultez le journal technique.": "The service is not responding after 120 s. Check the technical log.",
        "Le service s'est arrêté pendant le démarrage (code %@). Consultez le journal technique.": "The service stopped while starting (code %@). Check the technical log.",
        "Le test a échoué": "The test failed",
        "Les modèles Claude": "Claude models",
        "Les modèles GPT (ChatGPT)": "GPT models (ChatGPT)",
        "Les modèles Gemini de Google": "Google's Gemini models",
        "Les outils externes utilisant l'ancienne clé devront être mis à jour. Le service redémarrera et l'app sera mise à jour automatiquement.": "External tools using the old key will need updating. The service will restart and the app will be updated automatically.",
        "Limite atteinte chez le fournisseur (trop de requêtes ou crédit épuisé). Patientez un peu ou vérifiez votre compte chez le fournisseur.": "Provider limit reached (too many requests or no credit left). Wait a little or check your account with the provider.",
        "Limiter la longueur des réponses": "Limit response length",
        "Message": "Message",
        "Modifier le fournisseur": "Edit provider",
        "Modifier…": "Edit…",
        "Modèle testé : %@": "Model tested: %@",
        "Modèle utilisé pour cette conversation": "Model used for this conversation",
        "Modèles disponibles…": "Available Models…",
        "Ne modifiez ces réglages que si vous utilisez votre propre serveur LiteLLM.": "Only change these settings if you use your own LiteLLM server.",
        "Nom sous lequel ce modèle apparaît dans l'app et pour les autres outils.": "Name under which this model appears in the app and for other tools.",
        "Nouvelle conversation (⌘N)": "New conversation (⌘N)",
        "Ollama ne contient encore aucun modèle. Installez-en un depuis l'app Ollama (ex. llama3.3).": "Ollama has no models yet. Install one from the Ollama app (e.g. llama3.3).",
        "Ollama ne répond pas. Vérifiez qu'Ollama est installé et ouvert (ollama.com).": "Ollama is not responding. Make sure Ollama is installed and open (ollama.com).",
        "Options": "Options",
        "Options avancées": "Advanced options",
        "Ouvre l'installateur Apple. Quand il a terminé, cliquez sur « Réessayer ».": "Opens the Apple installer. When it finishes, click “Retry”.",
        "Par défaut (%@)": "Default (%@)",
        "Pas de connexion Internet.": "No Internet connection.",
        "Plus": "More",
        "Plus tard": "Later",
        "Posez votre question": "Ask your question",
        "Pour commencer, connectez un fournisseur d'IA (OpenAI, Anthropic, Gemini, Mistral, Ollama…). L'assistant vous guide en quelques étapes.": "To get started, connect an AI provider (OpenAI, Anthropic, Gemini, Mistral, Ollama…). The assistant guides you in a few steps.",
        "Comptes entreprise Microsoft": "Microsoft business accounts",
        "Problème": "Problem",
        "Précis": "Precise",
        "Préparation du service IA": "Preparing the AI service",
        "Python 3 est nécessaire. Installez les outils de développement Apple (gratuit, quelques minutes), puis réessayez.": "Python 3 is required. Install Apple's developer tools (free, a few minutes), then retry.",
        "Rechercher": "Search",
        "Redémarrer maintenant": "Restart now",
        "Redémarrez le service pour appliquer vos modifications.": "Restart the service to apply your changes.",
        "Regénérer la master key ?": "Regenerate the master key?",
        "Regénérer…": "Regenerate…",
        "Renommer": "Rename",
        "Renommer la conversation": "Rename conversation",
        "Renommer…": "Rename…",
        "Revenez en arrière pour corriger la clé API ou le modèle, puis réessayez.": "Go back to fix the API key or model, then retry.",
        "Réglages…": "Settings…",
        "Régénérer": "Regenerate",
        "Régénérer la réponse": "Regenerate response",
        "Réponse illisible : %@": "Unreadable response: %@",
        "Réponse invalide du serveur.": "Invalid server response.",
        "Réponses": "Responses",
        "Service IA local": "Local AI service",
        "Supprimer « %@ » ?": "Delete “%@”?",
        "Supprimer…": "Delete…",
        "Température : %@": "Temperature: %@",
        "Terminé": "Done",
        "Titre": "Title",
        "Un petit service (LiteLLM) tourne sur votre Mac et relaie vos messages vers le fournisseur choisi. Vos clés restent sur votre Mac.": "A small service (LiteLLM) runs on your Mac and relays your messages to the chosen provider. Your keys stay on your Mac.",
        "Utiliser aussi l'IA dans d'autres outils (facultatif)": "Also use the AI in other tools (optional)",
        "Utiliser le service local": "Use the local service",
        "Utilisé pour les nouvelles conversations. Vous pouvez en changer à tout moment dans la barre d'outils du chat.": "Used for new conversations. You can change it at any time in the chat toolbar.",
        "Voir les détails": "Show details",
        "Vous": "You",
        "Vous avez déjà une clé ? Collez-la ici : le fournisseur est reconnu automatiquement.": "Already have a key? Paste it here: the provider is recognized automatically.",
        "Vous discutez avec %@. Écrivez un message ci-dessous ou essayez une idée :": "You are chatting with %@. Type a message below or try an idea:",
        "clé %@": "key %@",
        "clé API manquante": "API key missing",
        "Écriture du config.yaml : %@": "Writing config.yaml: %@",
        "Écrivez votre message…": "Type your message…",
        "Régler la créativité": "Adjust creativity",
        "Désactivé : le modèle choisit lui-même (recommandé).": "Off: the model decides by itself (recommended).",
        "Le service IA ne connaît pas encore ce modèle. Redémarrez le service dans « Fournisseurs d'IA », puis réessayez.": "The AI service doesn't know this model yet. Restart the service in “AI Providers”, then retry.",
    ]
}
