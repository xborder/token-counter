import Foundation
import SwiftData

/// Watches `~/.claude/projects/` for new and modified JSONL log files.
/// Uses DispatchSource file monitoring and periodic directory scanning
/// to detect changes in real-time.
@Observable
final class ClaudeLogWatcher {

    /// Base directory for Claude Code project logs.
    static let defaultBasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/projects"
    }()

    private(set) var isWatching = false
    private var basePath: String
    private var fileOffsets: [String: UInt64] = [:]  // file path -> last parsed offset
    private var scanTimer: DispatchSourceTimer?
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var modelContext: ModelContext?

    /// Subagent metadata cache: agentId -> SubagentMeta
    private var subagentMetaCache: [String: ClaudeLogParser.SubagentMeta] = [:]

    init(basePath: String = ClaudeLogWatcher.defaultBasePath) {
        self.basePath = basePath
    }

    // MARK: - Public API

    /// Start watching for log changes. Performs an initial full scan.
    func start(modelContext: ModelContext) {
        guard !isWatching else { return }
        self.modelContext = modelContext
        isWatching = true

        // Initial full scan of all existing logs
        Task.detached(priority: .utility) { [weak self] in
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
        guard !result.turns.isEmpty else {
            fileOffsets[filePath] = result.newOffset
            return
        }

        guard let context = modelContext else { return }

        // Ensure project exists
        let project = findOrCreateProject(path: projectDir, context: context)

        // Ensure session exists
        let session = findOrCreateSession(
            sessionId: sessionId,
            project: project,
            firstTurn: result.turns.first,
            context: context
        )

        // Ingest turns
        for parsedTurn in result.turns {
            // Check if turn already exists (dedup safety)
            let turnId = parsedTurn.requestId
            let descriptor = FetchDescriptor<Turn>(predicate: #Predicate { $0.uuid == turnId })
            if let existing = try? context.fetch(descriptor), !existing.isEmpty {
                continue
            }

            let turn = Turn(
                uuid: turnId,
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
            turn.session = session

            // Resolve subagent type from meta cache
            if let agentId = parsedTurn.agentId, let meta = subagentMetaCache[agentId] {
                turn.subagentType = meta.agentType
            }

            // Cost will be calculated after insertion by CostCalculator
            context.insert(turn)

            // Update session timestamps
            if parsedTurn.timestamp < session.startedAt {
                session.startedAt = parsedTurn.timestamp
            }
            if parsedTurn.timestamp > session.lastActivityAt {
                session.lastActivityAt = parsedTurn.timestamp
            }

            // Update session metadata from first non-nil values
            if session.gitBranch == nil, let branch = parsedTurn.gitBranch {
                session.gitBranch = branch
            }
            if session.slug == nil, let slug = parsedTurn.slug {
                session.slug = slug
            }
            if session.cwd == nil, let cwd = parsedTurn.cwd {
                session.cwd = cwd
            }
        }

        try? context.save()
        fileOffsets[filePath] = result.newOffset
    }

    // MARK: - Model lookups

    private func findOrCreateProject(path: String, context: ModelContext) -> Project {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.path == path })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let displayName = Project.deriveDisplayName(from: path)
        let project = Project(path: path, displayName: displayName)
        context.insert(project)
        return project
    }

    private func findOrCreateSession(
        sessionId: String,
        project: Project,
        firstTurn: ClaudeLogParser.ParsedTurn?,
        context: ModelContext
    ) -> Session {
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.sessionId == sessionId })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let now = firstTurn.map { $0.timestamp } ?? Date()
        let session = Session(
            sessionId: sessionId,
            startedAt: now,
            lastActivityAt: now,
            gitBranch: firstTurn?.gitBranch,
            slug: firstTurn?.slug,
            cwd: firstTurn?.cwd
        )
        session.project = project
        context.insert(session)
        return session
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

    private func startDirectoryMonitor() {
        let fd = open(basePath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend],
            queue: DispatchQueue.global(qos: .utility)
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
}
