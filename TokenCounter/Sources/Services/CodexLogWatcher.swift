import Foundation

/// Watches `~/.codex/sessions/` for new and modified rollout JSONL files.
/// Scans the date-sharded directory (YYYY/MM/DD/rollout-*.jsonl) periodically.
final class CodexLogWatcher {

    static let defaultBasePath: String = {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] {
            return "\(codexHome)/sessions"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex/sessions"
    }()

    private(set) var isWatching = false
    private var basePath: String
    private let scanInterval: TimeInterval
    private let workQueue = DispatchQueue(label: "TokenCounter.CodexLogWatcher")
    private var fileOffsets: [String: UInt64] = [:]
    private var fileStates: [String: CodexLogParser.FileState] = [:]
    private var scanTimer: DispatchSourceTimer?
    private var store: TokenStore?
    private let costCalculator = CostCalculator()

    /// Callback invoked on the main queue whenever new turns are ingested.
    var onUpdate: (() -> Void)?

    init(basePath: String = CodexLogWatcher.defaultBasePath, scanInterval: TimeInterval = AppSettings.defaultRefreshInterval) {
        self.basePath = basePath
        self.scanInterval = scanInterval
    }

    // MARK: - Public API

    func start(store: TokenStore) {
        guard !isWatching else { return }
        self.store = store
        isWatching = true

        workQueue.async { [weak self] in
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
        guard let years = try? fm.contentsOfDirectory(atPath: basePath) else { return }

        for year in years where year.allSatisfy(\.isNumber) {
            let yearPath = "\(basePath)/\(year)"
            guard let months = try? fm.contentsOfDirectory(atPath: yearPath) else { continue }

            for month in months where month.allSatisfy(\.isNumber) {
                let monthPath = "\(yearPath)/\(month)"
                guard let days = try? fm.contentsOfDirectory(atPath: monthPath) else { continue }

                for day in days where day.allSatisfy(\.isNumber) {
                    scanDayDirectory("\(monthPath)/\(day)")
                }
            }
        }
    }

    private func scanDayDirectory(_ dayPath: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dayPath) else { return }

        for file in files where file.hasSuffix(".jsonl") && file.hasPrefix("rollout-") {
            parseAndIngest(filePath: "\(dayPath)/\(file)")
        }
    }

    private func parseAndIngest(filePath: String) {
        let offset = fileOffsets[filePath] ?? 0
        let state = fileStates[filePath] ?? CodexLogParser.FileState()
        let url = URL(fileURLWithPath: filePath)

        guard let result = try? CodexLogParser.parseFile(at: url, fromOffset: offset, state: state) else { return }
        fileOffsets[filePath] = result.newOffset
        fileStates[filePath] = result.fileState
        guard !result.turns.isEmpty, let store = store else { return }

        ingest(result.turns, into: store)
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

    private func ingest(_ turns: [CodexLogParser.ParsedTurn], into store: TokenStore) {
        let applyIngestion = {
            var didInsert = false
            for parsedTurn in turns {
                let project = store.findOrCreateProject(path: parsedTurn.projectPath)

                let session = store.findOrCreateCodexSession(
                    sessionId: parsedTurn.sessionId,
                    in: project,
                    timestamp: parsedTurn.timestamp,
                    sessionDate: parsedTurn.sessionDate
                )

                let turnId = "codex-\(parsedTurn.sessionId)-\(Int(parsedTurn.timestamp.timeIntervalSince1970 * 1000))"

                if let existingTurn = store.turn(uuid: turnId) {
                    if existingTurn.model == "codex" && parsedTurn.model != "codex" {
                        existingTurn.model = parsedTurn.model
                        existingTurn.estimatedCostUSD = self.costCalculator.cost(for: existingTurn)
                        didInsert = true
                    }
                    continue
                }

                let turn = Turn(
                    uuid: turnId,
                    timestamp: parsedTurn.timestamp,
                    model: parsedTurn.model,
                    provider: Provider.openai.rawValue
                )
                turn.inputTokens = parsedTurn.inputTokens
                turn.outputTokens = parsedTurn.outputTokens
                turn.cacheReadTokens = parsedTurn.cachedInputTokens
                turn.reasoningTokens = parsedTurn.reasoningTokens
                turn.estimatedCostUSD = self.costCalculator.cost(for: turn)

                store.insertTurn(turn, into: session)

                if parsedTurn.timestamp < session.startedAt { session.startedAt = parsedTurn.timestamp }
                if parsedTurn.timestamp > session.lastActivityAt { session.lastActivityAt = parsedTurn.timestamp }
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
}
