import Foundation

/// In-memory store of all token usage data, persisted to JSON on disk.
/// Replaces SwiftData — works with or without Xcode.
final class TokenStore {

    private let storeURL: URL

    /// All projects, keyed by directory path.
    private(set) var projects: [String: Project] = [:]

    /// All turns, keyed by requestId — for fast deduplication.
    private var turnIndex: [String: Turn] = [:]

    init(storeURL: URL? = nil) {
        if let url = storeURL {
            self.storeURL = url
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("TokenCounter", isDirectory: true)
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            self.storeURL = appSupport.appendingPathComponent("store.json")
        }
        load()
    }

    // MARK: - Lookups

    func project(for path: String) -> Project? { projects[path] }

    func session(sessionId: String) -> Session? {
        for project in projects.values {
            if let s = project.sessions.first(where: { $0.sessionId == sessionId }) {
                return s
            }
        }
        return nil
    }

    func hasTurn(uuid: String) -> Bool { turnIndex[uuid] != nil }

    /// All turns across all sessions, sorted chronologically.
    var allTurns: [Turn] { Array(turnIndex.values) }

    // MARK: - Mutations

    func findOrCreateProject(path: String) -> Project {
        if let p = projects[path] { return p }
        let p = Project(path: path, displayName: Project.deriveDisplayName(from: path))
        projects[path] = p
        return p
    }

    func findOrCreateSession(sessionId: String, in project: Project, firstTurn: ClaudeLogParser.ParsedTurn?) -> Session {
        if let s = project.sessions.first(where: { $0.sessionId == sessionId }) { return s }
        let now = firstTurn?.timestamp ?? Date()
        let s = Session(
            sessionId: sessionId,
            startedAt: now,
            lastActivityAt: now,
            gitBranch: firstTurn?.gitBranch,
            slug: firstTurn?.slug,
            cwd: firstTurn?.cwd
        )
        project.sessions.append(s)
        return s
    }

    func insertTurn(_ turn: Turn, into session: Session) {
        guard turnIndex[turn.uuid] == nil else { return }
        session.turns.append(turn)
        turnIndex[turn.uuid] = turn
    }

    // MARK: - Persistence

    private struct StoreData: Codable {
        let projects: [Project]
    }

    func save() {
        let data = StoreData(projects: Array(projects.values))
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: storeURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(StoreData.self, from: data) else { return }

        for project in decoded.projects {
            projects[project.path] = project
            for session in project.sessions {
                for turn in session.turns {
                    turnIndex[turn.uuid] = turn
                }
            }
        }
    }
}
