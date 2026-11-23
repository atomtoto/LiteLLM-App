import Foundation
import Combine
import Security
#if canImport(AppKit)
import AppKit
#endif

/// État du proxy LiteLLM local.
public enum ProxyState: Equatable, Sendable {
    case notInstalled
    case installing
    case installed
    case starting
    case running(external: Bool)
    case stopping
    case failed(String)
}

/// Journal cible pour la sortie des process.
public enum LogKind: Sendable {
    case install
    case proxy
}

/// Gère l'installation, le démarrage, l'arrêt et la configuration du proxy LiteLLM local.
@MainActor
public final class ProxyManager: ObservableObject {
    @Published public var state: ProxyState = .notInstalled
    @Published public var installLog = ""
    @Published public var proxyLog = ""
    @Published public var isHealthy = false
    @Published public var isStopping = false
    @Published public var settings = ProxySettingsStore.load()

    private let appSupport: URL
    private var process: Process?
    private var adoptedPID: Int32?
    private var healthTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?

    public init(appSupport: URL? = nil) {
        self.appSupport = appSupport ?? ProxyPaths.appSupport()
        refreshInstallState()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Chemins dérivés

    private var venvDir: URL { appSupport.appendingPathComponent("venv", isDirectory: true) }
    private var litellmBinary: URL { venvDir.appendingPathComponent("bin/litellm") }
    private var pipBinary: URL { venvDir.appendingPathComponent("bin/pip") }
    private var configFile: URL { appSupport.appendingPathComponent("config.yaml") }
    private var settingsFile: URL { appSupport.appendingPathComponent("proxy-settings.json") }
    private var pidFile: URL { appSupport.appendingPathComponent("proxy.pid") }

    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: litellmBinary.path)
    }

    public var baseURL: URL? {
        URL(string: "http://\(settings.host):\(settings.port)")
    }

    // MARK: - Master key

    /// Master key du proxy : lue du trousseau, ou générée et stockée la première fois.
    public func masterKey() -> String {
        if let key = KeychainService.load(account: KeychainService.masterKeyAccount), !key.isEmpty {
            return key
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let key = "sk-" + bytes.map { String(format: "%02x", $0) }.joined()
        try? KeychainService.save(account: KeychainService.masterKeyAccount, value: key)
        return key
    }

    // MARK: - État

    public func refreshInstallState() {
        switch state {
        case .installing, .starting, .running, .stopping:
            break
        default:
            state = isInstalled ? .installed : .notInstalled
        }
    }

    public var isBusy: Bool {
        switch state {
        case .installing, .starting, .stopping: return true
        default: return false
        }
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Vrai si l'on peut arrêter le proxy (process lancé par l'app, ou pid adopté encore vivant).
    public var canStop: Bool {
        if isStopping { return false }
        if let p = process, p.isRunning { return true }
        if let pid = adoptedPID, kill(pid, 0) == 0 { return true }
        return false
    }

    // MARK: - Installation

    /// Installe LiteLLM (`litellm[proxy]`) dans un venv dédié, en autonomie.
    public func install() {
        guard !isBusy, !isInstalled else { return }
        installTask = Task { [weak self] in
            guard let self else { return }
            await self.runInstall()
        }
    }

    /// Version awaitable de `install()` (utilisée par l'assistant de configuration).
    /// Renvoie true si le binaire litellm est présent à la fin.
    @discardableResult
    public func installAndWait() async -> Bool {
        guard !isInstalled, !isBusy else { return isInstalled }
        await runInstall()
        return isInstalled
    }

    private func runInstall() async {
        state = .installing
        installLog = ""
        do {
            let python = try Self.findPython()
            appendInstall("Création du venv avec \(python.path)…\n")
            _ = try await runProcess(executable: python, arguments: ["-m", "venv", venvDir.path],
                                     log: .install)
            guard FileManager.default.fileExists(atPath: pipBinary.path) else {
                throw ProxyError.venvCreationFailed
            }
            appendInstall("Installation de litellm[proxy] (cela peut prendre quelques minutes)…\n")
            let status = try await runProcess(executable: pipBinary,
                                              arguments: ["install", "--upgrade", "litellm[proxy]"],
                                              log: .install)
            guard status == 0, isInstalled else {
                throw ProxyError.pipInstallFailed(status)
            }
            appendInstall("Installation terminée.\n")
            state = .installed
        } catch {
            appendInstall("\nERREUR : \(error.localizedDescription)\n")
            state = .failed(error.localizedDescription)
        }
    }

    static func findPython() throws -> URL {
        let candidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    // MARK: - Démarrage / arrêt

    /// Écrit le config.yaml puis démarre le proxy.
    public func start() {
        guard !isBusy, isInstalled else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.startNow()
        }
    }

    public func autoStartIfNeeded() {
        guard settings.autoStart, isInstalled, !isRunning else { return }
        start()
    }

    /// Démarre le proxy puis attend qu'il réponde (ou échoue). Renvoie l'état final.
    @discardableResult
    public func startAndWait(timeout: TimeInterval = 180) async -> ProxyState {
        guard isInstalled, !isBusy else { return state }
        await startNow()
        return await waitUntilReady(timeout: timeout)
    }

    /// Attend que le proxy soit running (ou failed), au plus `timeout` secondes.
    @discardableResult
    public func waitUntilReady(timeout: TimeInterval = 180) async -> ProxyState {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .running = state { return state }
            if case .failed = state { return state }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return state
    }

    private func startNow() async {
        // Un proxy répond déjà sur ce port ?
        if await serverResponds() {
            adoptedPID = readPIDFile()
            state = .running(external: adoptedPID == nil)
            isHealthy = await checkHealth()
            appendProxy("Un proxy répond déjà sur \(settings.host):\(settings.port)"
                        + (adoptedPID != nil ? " — pid \(adoptedPID!) adopté (arrêtable)." : " — démarré hors de l'app.") + "\n")
            startHealthPolling()
            return
        }
        do {
            _ = try ProxyConfigWriter.write(settings: settings, masterKey: masterKey(), to: configFile)
        } catch {
            state = .failed("Écriture du config.yaml : \(error.localizedDescription)")
            return
        }

        state = .starting
        proxyLog = ""
        appendProxy("Démarrage : \(litellmBinary.path) --config \(configFile.path) --port \(settings.port) --host \(settings.host)\n")

        let process = Process()
        process.executableURL = litellmBinary
        process.arguments = ["--config", configFile.path, "--port", String(settings.port), "--host", settings.host]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in self?.appendProxy(text) }
            }
        }
        process.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                self.removePIDFile()
                self.appendProxy("\n[processus terminé, code \(p.terminationStatus)]\n")
                if case .running = self.state, self.process === p {
                    if await self.serverResponds() {
                        self.state = .running(external: true)
                    } else {
                        self.state = .installed
                        self.isHealthy = false
                    }
                } else if case .starting = self.state, self.process === p {
                    self.state = .failed("Le proxy s'est arrêté au démarrage (code \(p.terminationStatus)) — voir le journal.")
                    self.isHealthy = false
                }
            }
        }
        do {
            try process.run()
            self.process = process
            writePIDFile(Int32(process.processIdentifier))
        } catch {
            state = .failed("Lancement impossible : \(error.localizedDescription)")
            return
        }
        startHealthPolling()
    }

    public func stop() {
        guard !isStopping else { return }
        if let p = process, p.isRunning {
            isStopping = true
            state = .stopping
            p.terminate()
            Task { [weak self] in
                guard let self else { return }
                let deadline = Date().addingTimeInterval(5)
                while p.isRunning && Date() < deadline {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
                await self.finishStop()
            }
        } else if let pid = adoptedPID, kill(pid, 0) == 0 {
            isStopping = true
            state = .stopping
            Task { [weak self] in
                guard let self else { return }
                kill(pid, SIGTERM)
                let deadline = Date().addingTimeInterval(5)
                while kill(pid, 0) == 0 && Date() < deadline {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
                await self.finishStop()
            }
        }
    }

    private func finishStop() async {
        healthTask?.cancel()
        process = nil
        adoptedPID = nil
        removePIDFile()
        isHealthy = false
        isStopping = false
        state = .installed
        appendProxy("[arrêté]\n")
    }

    @objc private func appWillTerminate() {
        guard settings.stopOnQuit else { return }
        if let p = process, p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(3)
            while p.isRunning && Date() < deadline { usleep(100_000) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        } else if let pid = adoptedPID, kill(pid, 0) == 0 {
            kill(pid, SIGTERM)
            let deadline = Date().addingTimeInterval(3)
            while kill(pid, 0) == 0 && Date() < deadline { usleep(100_000) }
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    // MARK: - Santé

    /// Vrai si `/health` répond 2xx **avec la master key** (badge « health OK »).
    public func checkHealth() async -> Bool {
        guard let url = baseURL?.appendingPathComponent("health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let key = masterKey()
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// Vrai si le port répond en HTTP (n'importe quel statut) : détecte un serveur en ligne,
    /// même pendant le démarrage ou si `/health` exige une clé (401 sans master key).
    public func serverResponds() async -> Bool {
        guard let url = baseURL?.appendingPathComponent("health/liveliness") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              response is HTTPURLResponse else { return false }
        return true
    }

    private func startHealthPolling() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            while !Task.isCancelled {
                if await self.serverResponds() {
                    self.isHealthy = await self.checkHealth()
                    if case .starting = self.state {
                        self.state = .running(external: false)
                        self.appendProxy("[prêt — le serveur répond]\n")
                    }
                } else if case .starting = self.state, Date().timeIntervalSince(startedAt) > 120 {
                    self.state = .failed("Le proxy ne répond pas après 120 s — voir le journal ci-dessous.")
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: - Fichier pid

    private func writePIDFile(_ pid: Int32) {
        try? String(pid).write(to: pidFile, atomically: true, encoding: .utf8)
    }

    private func readPIDFile() -> Int32? {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return kill(pid, 0) == 0 ? pid : nil
    }

    private func removePIDFile() {
        try? FileManager.default.removeItem(at: pidFile)
    }

    // MARK: - Réglages

    public func saveSettings() {
        ProxySettingsStore.save(settings, to: settingsFile)
    }

    // MARK: - Process utilitaire

    /// Lance un process, stream sa sortie dans `log`, renvoie le code de sortie.
    private func runProcess(executable: URL, arguments: [String],
                            log: LogKind) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in self?.append(to: log, text: text) }
            }
        }
        final class StatusBox { var value: Int32 = -1 }
        let box = StatusBox()
        process.terminationHandler = { p in box.value = p.terminationStatus }
        try process.run()
        while process.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        handle.readabilityHandler = nil
        return box.value
    }

    private func append(to log: LogKind, text: String) {
        switch log {
        case .install: appendInstall(text)
        case .proxy: appendProxy(text)
        }
    }

    private func appendInstall(_ text: String) {
        installLog += text
        if installLog.count > 200_000 { installLog = String(installLog.suffix(100_000)) }
    }

    private func appendProxy(_ text: String) {
        proxyLog += text
        if proxyLog.count > 200_000 { proxyLog = String(proxyLog.suffix(100_000)) }
    }
}

public enum ProxyError: Error, LocalizedError, Sendable {
    case venvCreationFailed
    case pipInstallFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .venvCreationFailed:
            return "Impossible de créer l'environnement virtuel (pip introuvable)."
        case .pipInstallFailed(let code):
            return "pip a échoué (code \(code)) — voir le journal d'installation."
        }
    }
}
