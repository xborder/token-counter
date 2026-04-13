import Foundation

/// Watches `~/.pi/agent/sessions/` for new and modified Pi session JSONL files.
final class PiLogWatcher {

    static let defaultBasePath: String = {
        if let piHome = ProcessInfo.processInfo.environment["PI_HOME"] {
            return "\(piHome)/agent/sessions"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.pi/agent/sessions"
    }()

    private(set) var isWatching = false
    private var basePath: String
    private var fileOffsets: [String: UInt64] = [:]
    private var scanTimer: DispatchSourceTimer?
    private var store: TokenStore?
    private let costCalculator = CostCalculator()

    /// Callback invoked on the main queue whenever new turns are ingested.
    var onUpdate: (() -> Void)?

    init(basePath: String = PiLogWatcher.defaultBasePath) {
        self.basePath = basePath
    }

    // MARK: - Public API

    func start(store: TokenStore) {
        guard !isWatching else { return }
        self.store = store
        isWatching = true

        Task.detached(priority: .utility) { [weak self] in
            self?.performFullScan()
            self?.startPeriodicScan()
        }
    }

    func stop() {
        isWatching = false
        scanTimer?.cancel()
        scanTimer = nil
    }

    // MARK: - Scanning

    private func performFullScan() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: basePath) else { return }
        guard let projectSlugs = try? fm.contentsOfDirectory(atPath: basePath) else { return }

        for projectSlug in projectSlugs {
            let projectPath = "\(basePath)/\(projectSlug)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            scanProjectDirectory(projectPath)
        }
    }

    private func scanProjectDirectory(_ projectPath: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { return }

        for file in files where file.hasSuffix(".jsonl") {
            parseAndIngest(filePath: "\(projectPath)/\(file)")
        }
    }

    private func parseAndIngest(filePath: String) {
        let offset = fileOffsets[filePath] ?? 0
        let url = URL(fileURLWithPath: filePath)

        guard let result = try? PiLogParser.parseFile(at: url, fromOffset: offset) else { return }
        fileOffsets[filePath] = result.newOffset
        guard !result.turns.isEmpty, let store = store else { return }

        var didInsert = false
        for parsedTurn in result.turns {
            // Create/find project based on encoded slug
            let project = store.findOrCreateProject(path: parsedTurn.projectPath)

            // Use pi as the session slug, with a unique session per directory
            let sessionId = "pi-\(parsedTurn.projectPath)"
            let session = store.findOrCreatePiSession(
                sessionId: sessionId,
                in: project,
                timestamp: parsedTurn.timestamp
            )

            let turnId = "pi-\(parsedTurn.id)"
            guard !store.hasTurn(uuid: turnId) else { continue }

            let turn = Turn(
                uuid: turnId,
                timestamp: parsedTurn.timestamp,
                model: parsedTurn.model,
                provider: Provider.pi.rawValue
            )
            turn.inputTokens = parsedTurn.inputTokens
            turn.outputTokens = parsedTurn.outputTokens
            turn.cacheReadTokens = parsedTurn.cacheReadTokens
            turn.cacheCreationTokens = parsedTurn.cacheCreationTokens
            // Pi pre-computes cost, so use it directly
            turn.estimatedCostUSD = parsedTurn.estimatedCost

            store.insertTurn(turn, into: session)

            if parsedTurn.timestamp < session.startedAt { session.startedAt = parsedTurn.timestamp }
            if parsedTurn.timestamp > session.lastActivityAt { session.lastActivityAt = parsedTurn.timestamp }
            didInsert = true
        }

        if didInsert {
            store.save()
            DispatchQueue.main.async { self.onUpdate?() }
        }
    }

    // MARK: - Periodic scanning

    private func startPeriodicScan() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            guard let self, self.isWatching else { return }
            self.performFullScan()
        }
        timer.resume()
        self.scanTimer = timer
    }
}
