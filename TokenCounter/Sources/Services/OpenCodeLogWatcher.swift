import Foundation

/// Watches OpenCode SQLite database for new token usage.
/// Database location: `~/.local/share/opencode/opencode.db`
final class OpenCodeLogWatcher {

    static let defaultDatabasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/share/opencode/opencode.db"
    }()

    private(set) var isWatching = false
    private var databasePath: String
    private var scanTimer: DispatchSourceTimer?
    private var store: TokenStore?
    private let costCalculator = CostCalculator()

    /// Callback invoked on the main queue whenever new turns are ingested.
    var onUpdate: (() -> Void)?

    init(databasePath: String = OpenCodeLogWatcher.defaultDatabasePath) {
        self.databasePath = databasePath
    }

    // MARK: - Public API

    func start(store: TokenStore) {
        guard !isWatching else { return }
        self.store = store
        isWatching = true

        Task.detached(priority: .utility) { [weak self] in
            self?.performScan()
            self?.startPeriodicScan()
        }
    }

    func stop() {
        isWatching = false
        scanTimer?.cancel()
        scanTimer = nil
    }

    // MARK: - Scanning

    private func performScan() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: databasePath) else { return }

        guard let turns = try? OpenCodeLogParser.queryDatabase(at: databasePath) else { return }
        guard !turns.isEmpty, let store = store else { return }

        var didInsert = false
        for parsedTurn in turns {
            // Create/find project based on working directory
            let project = store.findOrCreateProject(path: parsedTurn.projectPath)

            let session = store.findOrCreateOpenCodeSession(
                sessionId: parsedTurn.sessionId,
                in: project,
                title: parsedTurn.sessionTitle,
                timestamp: parsedTurn.timestamp
            )

            let turnId = "opencode-\(parsedTurn.id)"
            guard !store.hasTurn(uuid: turnId) else { continue }

            let turn = Turn(
                uuid: turnId,
                timestamp: parsedTurn.timestamp,
                model: parsedTurn.model,
                provider: Provider.opencode.rawValue
            )
            turn.inputTokens = parsedTurn.inputTokens
            turn.outputTokens = parsedTurn.outputTokens
            turn.reasoningTokens = parsedTurn.reasoningTokens
            turn.cacheReadTokens = parsedTurn.cacheReadTokens
            turn.cacheCreationTokens = parsedTurn.cacheCreationTokens
            // OpenCode stores 0 for cost; compute it using CostCalculator
            turn.estimatedCostUSD = costCalculator.cost(for: turn)

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
            self.performScan()
        }
        timer.resume()
        self.scanTimer = timer
    }
}
