# LiteLLM-App

Client macOS natif (SwiftUI) et simple pour un proxy [LiteLLM](https://github.com/BerriAI/litellm). Nécessite macOS 15+.

## Fonctionnalités

- **Assistant de configuration au premier lancement** (bouton baguette pour le relancer) : choix de la langue, du fournisseur d'IA (OpenAI, Anthropic, Gemini, Mistral, Ollama, Azure, personnalisé — détection automatique depuis la clé collée), clé API + modèle, installation/démarrage du proxy, test réel du modèle, puis copie de la configuration (base URL + master key + modèle + exemple `curl`) pour brancher n'importe quel outil compatible OpenAI
- **Interface en français ou anglais** (sélecteur dans les réglages, effectif immédiatement)
- **Chat** avec streaming SSE (`POST /v1/chat/completions`), rendu Markdown natif, copie par menu contextuel, affichage du raisonnement (`reasoning_content`) et des tokens utilisés
- **Conversations persistantes** (SwiftData) dans une barre latérale `NavigationSplitView`
- **Modèles** récupérés via `GET /v1/models`, sélection par conversation, modèle par défaut dans les réglages
- **Réglages** (fenêtre native ⌘,.) : URL du serveur, clé API stockée dans le trousseau macOS, test de connexion (`/health`), température, tokens max, invite système
- Bouton stop pendant la génération (⌘↩ pour envoyer)
- **Proxy LiteLLM local autonome** (bouton CPU dans la barre latérale) :
  - *Installation autonome* : crée un venv dans `~/Library/Application Support/LiteLLM-App/venv` et installe `litellm[proxy]` via pip, avec journal en direct
  - *Démarrer / arrêter* le proxy (`litellm --config … --port …`), surveillance `/health`, arrêt propre à la fermeture de l'app (réglable), démarrage auto au lancement (réglable)
  - *Configuration* : cartes fournisseurs lisibles (fournisseur, modèle, clé API, test de la clé en un clic) + mode avancé (nom exposé, modèle LiteLLM, api_base), presets (OpenAI, Anthropic, Gemini, Mistral, Ollama, Azure, personnalisé), master key générée et stockée dans le trousseau, `config.yaml` régénéré à chaque démarrage (permissions 0600)
  - *Utiliser ce proxy ailleurs* : section dédiée pour copier base URL + master key + modèle (+ snippet `curl`) afin d'utiliser le proxy depuis n'importe quel outil compatible OpenAI — le proxy convertit automatiquement la requête dans le format du fournisseur

## Utilisation

Au premier lancement, l'assistant guide pas à pas : choisir un fournisseur (ou coller sa clé, reconnue automatiquement), choisir un modèle, puis l'app installe et démarre le service local, teste le modèle et se branche dessus toute seule. Il suffit ensuite de cliquer « Commencer à discuter ».

- **Fournisseurs d'IA** (bouton puce, ⇧⌘P) : ajouter/tester/modifier des fournisseurs, démarrer/arrêter le service, copier la configuration pour d'autres outils.
- **Nouvelle conversation** : ⌘N. Entrée envoie, ⌥Entrée va à la ligne, Échap arrête la génération. Clic droit sur une conversation pour la renommer ou la supprimer.
- Un bandeau en haut du chat signale un service arrêté ou en erreur, avec le bouton qui règle le problème.
- **Avec un proxy externe** : Réglages ▸ Connexion → URL + clé API → « Tester la connexion ».

## Build & test en ligne de commande

```sh
xcodebuild -project LiteLLMApp.xcodeproj -scheme LiteLLMApp -destination 'platform=macOS' build
xcodebuild -project LiteLLMApp.xcodeproj -scheme LiteLLMApp -destination 'platform=macOS' test
```

Ou ouvrir `LiteLLMApp.xcodeproj` dans Xcode.

## Structure

```
LiteLLMApp/
  LiteLLMApp.swift        point d'entrée (@main, scènes WindowGroup + Settings)
  ContentView.swift       NavigationSplitView : liste des conversations + chat
  Models/                 DTO Codable de l'API + parser SSE incrémental
  Services/               LiteLLMClient (URLSession, streaming), trousseau, réglages,
                          ProxyManager (install/start/stop du proxy local), ProxyConfig (YAML),
                          ProviderPresets (fournisseurs connus + détection de clé),
                          Localization (FR/EN), ShareConfig (snippet copiable)
  Data/                   modèles SwiftData (Conversation, ChatMessage)
  Views/                  ChatView, ChatViewModel, MessageRow, SettingsView, ModelsView,
                          ProxyView, OnboardingView (assistant 1er lancement),
                          ProviderFormView, ProviderCardView
LiteLLMAppTests/          tests unitaires (parser SSE, encodage/décodage API, presets,
                          localisation, snippet de configuration)
```
