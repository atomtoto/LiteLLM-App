# LiteLLM-App

Client macOS natif (SwiftUI) et simple pour un proxy [LiteLLM](https://github.com/BerriAI/litellm). Nécessite macOS 15+.

## Fonctionnalités

- **Chat** avec streaming SSE (`POST /v1/chat/completions`), rendu Markdown natif, copie par menu contextuel, affichage du raisonnement (`reasoning_content`) et des tokens utilisés
- **Conversations persistantes** (SwiftData) dans une barre latérale `NavigationSplitView`
- **Modèles** récupérés via `GET /v1/models`, sélection par conversation, modèle par défaut dans les réglages
- **Réglages** (fenêtre native ⌘,.) : URL du serveur, clé API stockée dans le trousseau macOS, test de connexion (`/health`), température, tokens max, invite système
- Bouton stop pendant la génération (⌘↩ pour envoyer)

## Utilisation

1. Lancer un proxy LiteLLM (ex. `litellm --port 4000`)
2. Ouvrir l'app → Réglages → indiquer l'URL (par défaut `http://localhost:4000`) et la clé API, puis « Tester la connexion »
3. « Nouvelle conversation », choisir un modèle, discuter

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
  Services/               LiteLLMClient (URLSession, streaming), trousseau, réglages
  Data/                   modèles SwiftData (Conversation, ChatMessage)
  Views/                  ChatView, ChatViewModel, MessageRow, SettingsView, ModelsView
LiteLLMAppTests/          tests unitaires (parser SSE, encodage/décodage API)
```
