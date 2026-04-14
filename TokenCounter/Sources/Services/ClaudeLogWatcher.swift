import Foundation

/// Watches `~/.claude/projects/` for new and modified JSONL log files.
/// Uses DispatchSource file monitoring and periodic directory scanning
/// to detect changes in real-time.
final class ClaudeLogWatcher {

    /// Base directory for Claude Code project logs.
    static let defaultBasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/projects"
    }()

    private(set) var isWatching = false
    private var basePath: String
    private let scanInterval: TimeInterval
    private let workQueue = DispatchQueue(label: "TokenCounter.ClaudeLogWatcher")
    private var fileOffsets: [String: UInt64] = [:]  // file path -> last parsed offset
    private var scanTimer: DispatchSourceTimer?
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var store: TokenStore?

    /// Callback invoked on the main queue whenever new turns are ingested.
    var onUpdate: (() -> Void)?

    /// Subagent metadata cache: agentId -> SubagentMeta
    private var subagentMetaCache: [String: ClaudeLogParser.SubagentMeta] = [:]

    init(basePath: String = ClaudeLogWatcher.defaultBasePath, scanInterval: TimeInterval = AppSettings.defaultRefreshInterval) {
        self.basePath = basePath
        self.scanInterval = scanInterval
    }

    // MARK: - Public API

    /// Start watching for log changes. Performs an initial full scan.
    func start(store: TokenStore) {
        guard !isWatching else { return }
        self.store = store
        isWatching = true

        // Initial full scan of all existing logs
        workQueue.async { [weak self] in
            self?.performFullScan()
            self?.startPeriodicScan()
            self?.startDirectoryMonitor()
        }
    }

    /// Stop watching.
    func stop() {
        isWatching = false
        scanTimer?.cancel()
        scanTimer = nil
        directoryMonitor?.cancel()
        directoryMonitor = nil
    }

    // MARK: - Directory scanning

    /// Scan all project directories and their JSONL files.
    private func performFullScan() {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: basePath) else { return }

        for projectDir in projectDirs {
            guard !projectDir.hasPrefix(".") else { continue }
            let projectPath = "\(basePath)/\(projectDir)"

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else { continue }

            processProjectDirectory(projectDir: projectDir, projectPath: projectPath)
        }
    }

    private func processProjectDirectory(projectDir: String, projectPath: String) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: projectPath) else { return }

        for item in contents {
            let fullPath = "\(projectPath)/\(item)"

            if item.hasSuffix(".jsonl") {
                // Main session JSONL file
                let sessionId = String(item.dropLast(6))  // remove ".jsonl"
                parseAndIngest(filePath: fullPath, projectDir: projectDir, sessionId: sessionId, isSubagent: false)
            } else {
                // Check for subagent directory: <session-uuid>/subagents/
                let subagentsPath = "\(fullPath)/subagents"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: subagentsPath, isDirectory: &isDir), isDir.boolValue {
                    processSubagentDirectory(subagentsPath: subagentsPath, projectDir: projectDir, sessionId: item)
                }
            }
        }
    }

    private func processSubagentDirectory(subagentsPath: String, projectDir: String, sessionId: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: subagentsPath) else { return }

        // Load meta.json files first
        for file in files where file.hasSuffix(".meta.json") {
            let metaPath = "\(subagentsPath)/\(file)"
            if let meta = ClaudeLogParser.parseSubagentMeta(at: URL(fileURLWithPath: metaPath)) {
                let agentId = String(file.dropLast(10))  // remove ".meta.json"
                subagentMetaCache[agentId] = meta
            }
        }

        // Parse JSONL files
        for file in files where file.hasSuffix(".jsonl") {
            let filePath = "\(subagentsPath)/\(file)"
            parseAndIngest(filePath: filePath, projectDir: projectDir, sessionId: sessionId, isSubagent: true)
        }
    }

    // MARK: - Parsing and ingestion

    private func parseAndIngest(filePath: String, projectDir: String, sessionId: String, isSubagent: Bool) {
        let offset = fileOffsets[filePath] ?? 0
        let url = URL(fileURLWithPath: filePath)

        guard let result = try? ClaudeLogParser.parseFile(at: url, fromOffset: offset) else { return }
        fileOffsets[filePath] = result.newOffset
        guard !result.turns.isEmpty, let store = store else { return }

        ingest(result.turns, into: store, projectDir: projectDir, sessionId: sessionId, isSubagent: isSubagent)
    }

    // MARK: - Periodic scanning

    private func startPeriodicScan() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + scanInterval, repeating: scanInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.isWatching else { return }
            self.performFullScan()
        }
        timer.resume()
        self.scanTimer = timer
    }

    private func startDirectoryMonitor() {
        let fd = open(basePath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend],
            queue: workQueue
        )
        source.setEventHandler { [weak self] in
            guard let self, self.isWatching else { return }
            self.performFullScan()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.directoryMonitor = source
    }

    private func ingest(
        _ turns: [ClaudeLogParser.ParsedTurn],
        into store: TokenStore,
        projectDir: String,
        sessionId: String,
        isSubagent: Bool
    ) {
        let metaCache = subagentMetaCache
        let applyIngestion = {
            let calculator = CostCalculator()
            let project = store.findOrCreateProject(path: projectDir)
            let session = store.findOrCreateSession(sessionId: sessionId, in: project, firstTurn: turns.first)

            var didInsert = false
            for parsedTurn in turns {
                let subagentType = parsedTurn.agentId.flatMap { metaCache[$0]?.agentType }

                if let existingTurn = store.turn(uuid: parsedTurn.requestId) {
                    self.merge(parsedTurn, into: existingTurn, isSubagent: isSubagent, subagentType: subagentType)
                    existingTurn.estimatedCostUSD = calculator.cost(for: existingTurn)

                    if parsedTurn.timestamp > session.lastActivityAt { session.lastActivityAt = parsedTurn.timestamp }
                    if session.gitBranch == nil { session.gitBranch = parsedTurn.gitBranch }
                    if session.slug == nil { session.slug = parsedTurn.slug }
                    if session.cwd == nil { session.cwd = parsedTurn.cwd }
                    didInsert = true
                    continue
                }

                let turn = Turn(
                    uuid: parsedTurn.requestId,
                    timestamp: parsedTurn.timestamp,
                    model: parsedTurn.model,
                    provider: Provider.claude.rawValue
                )
                turn.inputTokens = parsedTurn.inputTokens
                turn.outputTokens = parsedTurn.outputTokens
                turn.cacheCreationTokens = parsedTurn.cacheCreationTokens
                turn.cacheReadTokens = parsedTurn.cacheReadTokens
                turn.cacheCreation5mTokens = parsedTurn.cacheCreation5mTokens
                turn.cacheCreation1hTokens = parsedTurn.cacheCreation1hTokens
                turn.isSubagent = isSubagent
                turn.estimatedCostUSD = calculator.cost(for: turn)

                if let subagentType {
                    turn.subagentType = subagentType
                }

                store.insertTurn(turn, into: session)

                if parsedTurn.timestamp < session.startedAt { session.startedAt = parsedTurn.timestamp }
                if parsedTurn.timestamp > session.lastActivityAt { session.lastActivityAt = parsedTurn.timestamp }
                if session.gitBranch == nil { session.gitBranch = parsedTurn.gitBranch }
                if session.slug == nil { session.slug = parsedTurn.slug }
                if session.cwd == nil { session.cwd = parsedTurn.cwd }
                didInsert = true
            }

            if didInsert {
                store.save()
                self.onUpdate?()
            }
        }

        if Thread.isMainThread {
            applyIngestion()
        } else {
            DispatchQueue.main.sync(execute: applyIngestion)
        }
    }

    private func merge(
        _ parsedTurn: ClaudeLogParser.ParsedTurn,
        into turn: Turn,
        isSubagent: Bool,
        subagentType: String?
    ) {
        turn.model = parsedTurn.model
        turn.inputTokens = max(turn.inputTokens, parsedTurn.inputTokens)
        turn.outputTokens = max(turn.outputTokens, parsedTurn.outputTokens)
        turn.cacheCreationTokens = max(turn.cacheCreationTokens, parsedTurn.cacheCreationTokens)
        turn.cacheReadTokens = max(turn.cacheReadTokens, parsedTurn.cacheReadTokens)
        turn.cacheCreation5mTokens = max(turn.cacheCreation5mTokens, parsedTurn.cacheCreation5mTokens)
        turn.cacheCreation1hTokens = max(turn.cacheCreation1hTokens, parsedTurn.cacheCreation1hTokens)
        turn.isSubagent = turn.isSubagent || isSubagent

        if let subagentType {
            turn.subagentType = subagentType
        }
    }
}
