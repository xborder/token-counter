import XCTest
@testable import TokenCounter

final class ClaudeLogParserTests: XCTestCase {

    var fixtureURL: URL!

    override func setUp() {
        super.setUp()
        fixtureURL = Bundle.module.url(forResource: "sample-session", withExtension: "jsonl")!
    }

    // MARK: - Deduplication tests

    func testDeduplicatesByRequestId() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)

        // req_test1 has 3 streaming chunks (assist-001a, 001b, 001c) -> should produce 1 turn
        // req_test2 has 1 line -> 1 turn
        // req_sub1 has 1 line -> 1 turn
        XCTAssertEqual(result.turns.count, 3, "Should have 3 turns after deduplication")
    }

    func testKeepsLastStreamingChunk() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)

        // req_test1's last chunk has output_tokens=150
        let turn1 = result.turns.first { $0.requestId == "req_test1" }
        XCTAssertNotNil(turn1)
        XCTAssertEqual(turn1?.outputTokens, 150, "Should keep the last chunk's output_tokens (150)")
        XCTAssertEqual(turn1?.inputTokens, 3)
        XCTAssertEqual(turn1?.cacheCreationTokens, 1000)
    }

    // MARK: - Token field extraction

    func testExtractsAllTokenFields() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)

        let turn2 = result.turns.first { $0.requestId == "req_test2" }
        XCTAssertNotNil(turn2)
        XCTAssertEqual(turn2?.inputTokens, 10)
        XCTAssertEqual(turn2?.outputTokens, 300)
        XCTAssertEqual(turn2?.cacheCreationTokens, 200)
        XCTAssertEqual(turn2?.cacheReadTokens, 800)
        XCTAssertEqual(turn2?.cacheCreation5mTokens, 200)
        XCTAssertEqual(turn2?.cacheCreation1hTokens, 0)
    }

    func testExtractsModel() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)

        let turn1 = result.turns.first { $0.requestId == "req_test1" }
        XCTAssertEqual(turn1?.model, "claude-opus-4-6")

        let subTurn = result.turns.first { $0.requestId == "req_sub1" }
        XCTAssertEqual(subTurn?.model, "claude-haiku-4-5-20251001")
    }

    // MARK: - Subagent detection

    func testDetectsSubagentTurns() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)

        let subTurn = result.turns.first { $0.requestId == "req_sub1" }
        XCTAssertNotNil(subTurn)
        XCTAssertTrue(subTurn?.isSubagent ?? false, "Sidechain turn should be marked as subagent")
        XCTAssertEqual(subTurn?.agentId, "agent-sub-001")

        let mainTurn = result.turns.first { $0.requestId == "req_test1" }
        XCTAssertFalse(mainTurn?.isSubagent ?? true, "Non-sidechain turn should not be marked as subagent")
    }

    // MARK: - Metadata extraction

    func testExtractsSessionMetadata() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)

        let turn = result.turns.first!
        XCTAssertEqual(turn.sessionId, "test-session-001")
        XCTAssertEqual(turn.gitBranch, "main")
        XCTAssertEqual(turn.slug, "test-session")
        XCTAssertEqual(turn.cwd, "/home/user/test")
    }

    // MARK: - Timestamp parsing

    func testParsesTimestamps() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)

        let turn1 = result.turns.first { $0.requestId == "req_test1" }
        XCTAssertNotNil(turn1?.timestamp)

        // Verify correct ordering
        let timestamps = result.turns.map(\.timestamp)
        let sorted = timestamps.sorted()
        XCTAssertEqual(timestamps, sorted, "Turns should be in chronological order")
    }

    // MARK: - Incremental parsing

    func testIncrementalParsing() throws {
        // Parse full file first
        let fullResult = try ClaudeLogParser.parseFile(at: fixtureURL)
        XCTAssertGreaterThan(fullResult.newOffset, 0)

        // Parsing from end offset should return no new turns
        let incrementalResult = try ClaudeLogParser.parseFile(at: fixtureURL, fromOffset: fullResult.newOffset)
        XCTAssertEqual(incrementalResult.turns.count, 0, "No new turns after full parse")
    }

    // MARK: - Edge cases

    func testHandlesEmptyFile() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty.jsonl")
        FileManager.default.createFile(atPath: tmpURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let result = try ClaudeLogParser.parseFile(at: tmpURL)
        XCTAssertEqual(result.turns.count, 0)
    }

    func testSkipsMalformedLines() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("malformed.jsonl")
        let content = """
        not valid json
        {"type":"assistant","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":5,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"req_good","uuid":"good-uuid","timestamp":"2026-04-11T11:42:10.000Z","sessionId":"test"}
        {broken json line
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let result = try ClaudeLogParser.parseFile(at: tmpURL)
        XCTAssertEqual(result.turns.count, 1, "Should parse the one valid line and skip malformed ones")
    }

    // MARK: - Filters non-assistant lines

    func testFiltersNonAssistantLines() throws {
        let result = try ClaudeLogParser.parseFile(at: fixtureURL)

        // The fixture has queue-operation and user lines that should be filtered out
        // Only assistant lines with usage should be counted
        for turn in result.turns {
            XCTAssertFalse(turn.model.isEmpty, "All parsed turns should have a model")
        }
    }
}
