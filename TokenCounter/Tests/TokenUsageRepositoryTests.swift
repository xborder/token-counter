import Testing
import Foundation
@testable import TokenCounter

struct TokenUsageRepositoryTests {

    private func createTestStore() -> TokenStore {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_test_\(UUID().uuidString).json")
        return TokenStore(storeURL: tmpURL)
    }

    // MARK: - Bugs fixed in this session

    @Test func projectsFilteredByTimeRangeOmitOldProjects() throws {
        let store = createTestStore()

        // Create project with old session (outside today's range)
        // Use a path that will derive to a recognizable display name
        let oldProject = store.findOrCreateProject(path: "-Users-test-old-project")
        let oldSession = store.findOrCreateSession(
            sessionId: "old-session",
            in: oldProject,
            firstTurn: nil
        )

        // Add turn from yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oldTurn = Turn(
            uuid: "turn-1",
            timestamp: yesterday,
            model: "claude-opus-4-6",
            provider: "claude"
        )
        oldTurn.inputTokens = 100
        store.insertTurn(oldTurn, into: oldSession)

        // Create project with recent session (within today's range)
        let recentProject = store.findOrCreateProject(path: "-Users-test-recent-project")
        let recentSession = store.findOrCreateSession(
            sessionId: "recent-session",
            in: recentProject,
            firstTurn: nil
        )
        let now = Date()
        let recentTurn = Turn(
            uuid: "turn-2",
            timestamp: now,
            model: "claude-opus-4-6",
            provider: "claude"
        )
        recentTurn.inputTokens = 100
        store.insertTurn(recentTurn, into: recentSession)

        let repo = TokenUsageRepository(store: store)

        // Today filter should exclude old project
        let todayProjects = repo.projects(for: .today)
        #expect(!todayProjects.map(\.displayName).contains("old-project"))
        #expect(todayProjects.map(\.displayName).contains("recent-project"))

        // All-time should include both
        let allProjects = repo.projects(for: .allTime)
        #expect(allProjects.count == 2)
    }

    @Test func sessionsFilteredByTimeRangeInProject() throws {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "test-project")

        // Create old session
        let oldSession = store.findOrCreateSession(
            sessionId: "old-session",
            in: project,
            firstTurn: nil
        )
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oldTurn = Turn(
            uuid: "turn-old",
            timestamp: yesterday,
            model: "claude-opus-4-6",
            provider: "claude"
        )
        store.insertTurn(oldTurn, into: oldSession)

        // Create recent session
        let recentSession = store.findOrCreateSession(
            sessionId: "recent-session",
            in: project,
            firstTurn: nil
        )
        let now = Date()
        let recentTurn = Turn(
            uuid: "turn-recent",
            timestamp: now,
            model: "claude-opus-4-6",
            provider: "claude"
        )
        store.insertTurn(recentTurn, into: recentSession)

        let repo = TokenUsageRepository(store: store)

        // Today filter should only show recent session
        let todaySessions = repo.sessions(for: project, timeRange: .today)
        #expect(todaySessions.map(\.sessionId).contains("recent-session"))
        #expect(!todaySessions.map(\.sessionId).contains("old-session"))

        // All-time should show both
        let allSessions = repo.sessions(for: project, timeRange: .allTime)
        #expect(allSessions.map(\.sessionId).contains("old-session"))
        #expect(allSessions.map(\.sessionId).contains("recent-session"))
    }

    @Test func turnsFilteredByTimeRangeWithinSession() throws {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "test-project")
        let session = store.findOrCreateSession(
            sessionId: "test-session",
            in: project,
            firstTurn: nil
        )

        // Add old turn
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oldTurn = Turn(
            uuid: "turn-old",
            timestamp: yesterday,
            model: "claude-opus-4-6",
            provider: "claude"
        )
        oldTurn.inputTokens = 1000
        store.insertTurn(oldTurn, into: session)

        // Add recent turn
        let now = Date()
        let recentTurn = Turn(
            uuid: "turn-recent",
            timestamp: now,
            model: "claude-opus-4-6",
            provider: "claude"
        )
        recentTurn.inputTokens = 500
        store.insertTurn(recentTurn, into: session)

        let repo = TokenUsageRepository(store: store)

        // Today filter should only include recent turn
        let todayTurns = repo.turns(for: session, timeRange: .today)
        #expect(todayTurns.count == 1)
        #expect(todayTurns[0].uuid == "turn-recent")

        // All-time should include both
        let allTurns = repo.turns(for: session, timeRange: .allTime)
        #expect(allTurns.count == 2)
    }

    @Test func sessionBreakdownTotalsMatchHeaderWhenTimeRangeApplied() throws {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "test-project")
        let session = store.findOrCreateSession(
            sessionId: "test-session",
            in: project,
            firstTurn: nil
        )

        // Add old turn outside today's range
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oldTurn = Turn(
            uuid: "turn-old",
            timestamp: yesterday,
            model: "claude-opus-4-6",
            provider: "claude"
        )
        oldTurn.inputTokens = 10000
        store.insertTurn(oldTurn, into: session)

        // Add today's turn
        let now = Date()
        let recentTurn = Turn(
            uuid: "turn-recent",
            timestamp: now,
            model: "claude-opus-4-6",
            provider: "claude"
        )
        recentTurn.inputTokens = 5000
        store.insertTurn(recentTurn, into: session)

        let repo = TokenUsageRepository(store: store)

        // Get summary for today
        let todaySummary = repo.summary(for: .today)
        // Should only count today's turn (5000 input tokens)
        #expect(todaySummary.inputTokens == 5000)

        // Get turns for session filtered to today
        let todayTurns = repo.turns(for: session, timeRange: .today)
        let todaySessionTotal = todayTurns.reduce(0) { $0 + $1.inputTokens }
        // Session breakdown should match header
        #expect(todaySessionTotal == todaySummary.inputTokens)
    }

    // MARK: - Codex model extraction

    @Test("Codex parser extracts gpt-5.4 model from turn_context event")
    func codexParserExtractsModelFromTurnContext() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_codex_model_\(UUID().uuidString).jsonl")
        let content = """
        {"timestamp":"2026-04-10T09:17:28.541Z","type":"turn_context","payload":{"turn_id":"019d76ae-82d5-78c2-b190-5866df491656","model":"gpt-5.4"}}
        {"timestamp":"2026-04-10T09:17:29.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let result = try CodexLogParser.parseFile(at: tmpURL)
        #expect(result.turns.count == 1)
        #expect(result.turns[0].model == "gpt-5.4")
    }

    @Test("Codex parser extracts gpt-5.3-codex model from turn_context event")
    func codexParserExtractsGpt53Model() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_codex_gpt53_\(UUID().uuidString).jsonl")
        let content = """
        {"timestamp":"2026-04-10T09:17:28.541Z","type":"turn_context","payload":{"turn_id":"019d76ae-82d5-78c2-b190-5866df491656","model":"gpt-5.3-codex"}}
        {"timestamp":"2026-04-10T09:17:29.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":75,"reasoning_output_tokens":10,"total_tokens":285}}}}
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let result = try CodexLogParser.parseFile(at: tmpURL)
        #expect(result.turns.count == 1)
        #expect(result.turns[0].model == "gpt-5.3-codex")
    }

    @Test("Codex parser maintains model across multiple token_count events")
    func codexParserMaintainsModelAcrossMultipleTurns() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_codex_multi_\(UUID().uuidString).jsonl")
        let content = """
        {"timestamp":"2026-04-10T09:17:28.541Z","type":"turn_context","payload":{"turn_id":"019d76ae-82d5-78c2-b190-5866df491656","model":"gpt-5.4"}}
        {"timestamp":"2026-04-10T09:17:29.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}
        {"timestamp":"2026-04-10T09:17:30.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":75,"reasoning_output_tokens":0,"total_tokens":275}}}}
        {"timestamp":"2026-04-10T09:17:31.000Z","type":"turn_context","payload":{"turn_id":"019d76b8-252b-7da3-be35-7d70b9655ece","model":"gpt-5.3-codex"}}
        {"timestamp":"2026-04-10T09:17:32.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":0,"output_tokens":100,"reasoning_output_tokens":5,"total_tokens":405}}}}
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let result = try CodexLogParser.parseFile(at: tmpURL)
        #expect(result.turns.count == 3)
        #expect(result.turns[0].model == "gpt-5.4")
        #expect(result.turns[1].model == "gpt-5.4")
        #expect(result.turns[2].model == "gpt-5.3-codex")
    }
}
