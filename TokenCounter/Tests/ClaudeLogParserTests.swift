import Testing
import Foundation
@testable import TokenCounter

struct ClaudeLogParserTests {

    private var fixtureURL: URL {
        Bundle.module.url(forResource: "sample-session", withExtension: "jsonl")!
    }

    // MARK: - Deduplication

    @Test func deduplicatesByRequestId() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)
        // req_test1 has 3 streaming chunks -> 1 turn; req_test2 -> 1; req_sub1 -> 1
        #expect(result.turns.count == 3)
    }

    @Test func keepsLastStreamingChunk() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)
        let turn1 = result.turns.first { $0.requestId == "req_test1" }
        #expect(turn1 != nil)
        #expect(turn1?.outputTokens == 150)  // last chunk has 150
        #expect(turn1?.inputTokens == 3)
        #expect(turn1?.cacheCreationTokens == 1000)
    }

    // MARK: - Token field extraction

    @Test func extractsAllTokenFields() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)
        let turn2 = result.turns.first { $0.requestId == "req_test2" }
        #expect(turn2 != nil)
        #expect(turn2?.inputTokens == 10)
        #expect(turn2?.outputTokens == 300)
        #expect(turn2?.cacheCreationTokens == 200)
        #expect(turn2?.cacheReadTokens == 800)
        #expect(turn2?.cacheCreation5mTokens == 200)
        #expect(turn2?.cacheCreation1hTokens == 0)
    }

    @Test func extractsModel() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)
        let turn1 = result.turns.first { $0.requestId == "req_test1" }
        #expect(turn1?.model == "claude-opus-4-6")
        let subTurn = result.turns.first { $0.requestId == "req_sub1" }
        #expect(subTurn?.model == "claude-haiku-4-5-20251001")
    }

    // MARK: - Subagent detection

    @Test func detectsSubagentTurns() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)
        let subTurn = result.turns.first { $0.requestId == "req_sub1" }
        #expect(subTurn != nil)
        #expect(subTurn?.isSubagent == true)
        #expect(subTurn?.agentId == "agent-sub-001")
        let mainTurn = result.turns.first { $0.requestId == "req_test1" }
        #expect(mainTurn?.isSubagent == false)
    }

    // MARK: - Metadata extraction

    @Test func extractsSessionMetadata() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)
        let turn = try #require(result.turns.first)
        #expect(turn.sessionId == "test-session-001")
        #expect(turn.gitBranch == "main")
        #expect(turn.slug == "test-session")
        #expect(turn.cwd == "/home/user/test")
    }

    // MARK: - Timestamps

    @Test func parsesTimestampsInOrder() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)
        let timestamps = result.turns.map(\.timestamp)
        #expect(timestamps == timestamps.sorted())
    }

    // MARK: - Incremental parsing

    @Test func incrementalParsing() throws {
        let fullResult = try ClaudeLogParser.parseFile(at: fixtureURL)
        #expect(fullResult.newOffset > 0)
        let incResult = try ClaudeLogParser.parseFile(at: fixtureURL, fromOffset: fullResult.newOffset)
        #expect(incResult.turns.count == 0)
    }

    // MARK: - Edge cases

    @Test func handlesEmptyFile() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_empty_\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: tmpURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let result = try ClaudeLogParser.parseFile(at: tmpURL)
        #expect(result.turns.count == 0)
    }

    @Test func skipsMalformedLines() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_malformed_\(UUID().uuidString).jsonl")
        let content = """
        not valid json
        {"type":"assistant","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":5,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"req_good","uuid":"good-uuid","timestamp":"2026-04-11T11:42:10.000Z","sessionId":"test"}
        {broken json line
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let result = try ClaudeLogParser.parseFile(at: tmpURL)
        #expect(result.turns.count == 1)
    }

    @Test func filtersNonAssistantLines() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)
        for turn in result.turns {
            #expect(!turn.model.isEmpty)
        }
    }
}
