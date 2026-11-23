# LiteLLM-App

Client macOS natif (SwiftUI) et simple pour un proxy [LiteLLM](https://github.com/BerriAI/litellm). Nécessite macOS 15+.

## Fonctionnalités

- **Chat** avec streaming SSE (`POST /v1/chat/completions`), rendu Markdown natif, copie par menu contextuel, affichage du raisonnement (`reasoning_content`) et des tokens utilisés
- **Conversations persistantes** (SwiftData) dans une barre latérale `NavigationSplitView`
- **Modèles** récupérés via `GET /v1/models`, sélection par conversation, modèle par défaut dans les réglages
- **Réglages** (fenêtre native ⌘,.) : URL du serveur, clé API stockée dans le trousseau macOS, test de connexion (`/health`), température, tokens max, invite système
- Bouton stop pendant la génération (⌘↩ pour envoyer)
- **Proxy LiteLLM local autonome** (bouton CPU dans la barre latérale) :
  - *Installation autonome* : crée un venv dans `~/Library/Application Support/LiteLLM-App/venv` et installe `litellm[proxy]` via pip, avec journal en direct
  - *Démarrer / arrêter* le proxy (`litellm --config … --port …`), surveillance `/health`, arrêt propre à la fermeture de l'app (réglable), démarrage auto au lancement (réglable)
  - *Configuration* : liste des modèles (nom exposé, modèle LiteLLM, clé API fournisseur, api_base) avec presets (OpenAI, Anthropic, Gemini, Mistral, Ollama…), master key générée et stockée dans le trousseau, `config.yaml` régénéré à chaque démarrage (permissions 0600)

## Utilisation

**Avec le proxy géré par l'app** (recommandé) : ouvrir le panneau « Proxy LiteLLM local » (bouton CPU) → « Installer LiteLLM » → ajouter des modèles → « Démarrer » → « Utiliser comme serveur » → la clé API des réglages doit contenir la master key affichée dans le panneau.

**Avec un proxy externe** : lancer `litellm --port 4000`, puis dans l'app → Réglages → indiquer l'URL (par défaut `http://localhost:4000`) et la clé API, puis « Tester la connexion ».

Ensuite : « Nouvelle conversation », choisir un modèle, discuter.

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
                          ProxyManager (install/start/stop du proxy local), ProxyConfig (YAML)
  Data/                   modèles SwiftData (Conversation, ChatMessage)
  Views/                  ChatView, ChatViewModel, MessageRow, SettingsView, ModelsView
LiteLLMAppTests/          tests unitaires (parser SSE, encodage/décodage API)
```
