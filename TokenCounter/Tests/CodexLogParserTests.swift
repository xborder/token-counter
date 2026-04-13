import Testing
import Foundation
@testable import TokenCounter

struct CodexLogParserTests {

    private var fixtureURL: URL {
        Bundle.module.url(forResource: "sample-codex-session", withExtension: "jsonl")!
    }

    // MARK: - Basic parsing

    @Test func parsesTokenCountEvents() throws {
        let result = try CodexLogParser.parseFile(at: fixtureURL)
        // 3 token_count events -> 3 turns
        #expect(result.turns.count == 3)
    }

    @Test func extractsLastTokenUsageDirectly() throws {
        let result = try CodexLogParser.parseFile(at: fixtureURL)
        // First turn uses last_token_usage directly
        let turn1 = result.turns[0]
        #expect(turn1.inputTokens == 400)       // 500 - 100 cached
        #expect(turn1.cachedInputTokens == 100)
        #expect(turn1.outputTokens == 200)
        #expect(turn1.reasoningTokens == 50)
    }

    @Test func extractsSecondTurnFromLastTokenUsage() throws {
        let result = try CodexLogParser.parseFile(at: fixtureURL)
        let turn2 = result.turns[1]
        #expect(turn2.inputTokens == 500)        // 700 - 200 cached
        #expect(turn2.cachedInputTokens == 200)
        #expect(turn2.outputTokens == 300)
        #expect(turn2.reasoningTokens == 70)
    }

    // MARK: - Delta calculation from total_token_usage

    @Test func computesDeltaFromTotalUsage() throws {
        let result = try CodexLogParser.parseFile(at: fixtureURL)
        // Third event has only total_token_usage, so delta computed from previous total
        let turn3 = result.turns[2]
        let deltaInput = 2000 - 1200     // 800
        let deltaCached = 600 - 300       // 300
        #expect(turn3.inputTokens == deltaInput - deltaCached) // 500
        #expect(turn3.cachedInputTokens == deltaCached)        // 300
        #expect(turn3.outputTokens == 800 - 500)               // 300
        #expect(turn3.reasoningTokens == 200 - 120)            // 80
    }

    // MARK: - Model extraction

    @Test func capturesModelFromTurnContext() throws {
        let result = try CodexLogParser.parseFile(at: fixtureURL)
        for turn in result.turns {
            #expect(turn.model == "codex-mini")
        }
    }

    // MARK: - Session ID extraction

    @Test func extractsSessionIdFromFilename() throws {
        let result = try CodexLogParser.parseFile(at: fixtureURL)
        // Fixture filename is "sample-codex-session.jsonl", not "rollout-*"
        // so sessionId should be the filename without extension
        #expect(!result.turns.isEmpty)
        #expect(result.turns[0].sessionId == "sample-codex-session")
    }

    // MARK: - Incremental parsing

    @Test func incrementalParsing() throws {
        let fullResult = try CodexLogParser.parseFile(at: fixtureURL)
        #expect(fullResult.newOffset > 0)
        let incResult = try CodexLogParser.parseFile(at: fixtureURL, fromOffset: fullResult.newOffset)
        #expect(incResult.turns.count == 0)
    }

    // MARK: - Timestamps

    @Test func parsesTimestampsInOrder() throws {
        let result = try CodexLogParser.parseFile(at: fixtureURL)
        let timestamps = result.turns.map(\.timestamp)
        #expect(timestamps == timestamps.sorted())
    }

    // MARK: - Edge cases

    @Test func handlesEmptyFile() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_codex_empty_\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: tmpURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let result = try CodexLogParser.parseFile(at: tmpURL)
        #expect(result.turns.count == 0)
    }

    @Test func skipsNonTokenCountEvents() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_codex_other_\(UUID().uuidString).jsonl")
        let content = """
        {"timestamp":"2026-04-11T10:00:00.000Z","type":"event_msg","payload":{"type":"session_start","info":{}}}
        {"timestamp":"2026-04-11T10:00:01.000Z","type":"event_msg","payload":{"type":"other_event","info":{}}}
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let result = try CodexLogParser.parseFile(at: tmpURL)
        #expect(result.turns.count == 0)
    }

    @Test func skipsMalformedLines() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_codex_malformed_\(UUID().uuidString).jsonl")
        let content = """
        not valid json at all
        {"timestamp":"2026-04-11T10:00:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}
        {broken
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let result = try CodexLogParser.parseFile(at: tmpURL)
        #expect(result.turns.count == 1)
    }

    // MARK: - Incremental model state carry-over

    @Test func carriesModelStateAcrossIncrementalReads() throws {
        // Write a file with turn_context followed by token_count
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_codex_incr_model_\(UUID().uuidString).jsonl")
        let chunk1 = """
        {"timestamp":"2026-04-11T10:00:00.000Z","type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5.4"}}
        {"timestamp":"2026-04-11T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}

        """
        try chunk1.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // First read: gets model from turn_context
        let result1 = try CodexLogParser.parseFile(at: tmpURL)
        #expect(result1.turns.count == 1)
        #expect(result1.turns[0].model == "gpt-5.4")
        #expect(result1.fileState.model == "gpt-5.4")

        // Append more data without a turn_context
        let chunk2 = """
        {"timestamp":"2026-04-11T10:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":80,"reasoning_output_tokens":0,"total_tokens":280}}}}

        """
        let fileHandle = try FileHandle(forWritingTo: tmpURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write(Data(chunk2.utf8))
        try fileHandle.close()

        // Second read with carried state — model should still be gpt-5.4
        let result2 = try CodexLogParser.parseFile(at: tmpURL, fromOffset: result1.newOffset, state: result1.fileState)
        #expect(result2.turns.count == 1)
        #expect(result2.turns[0].model == "gpt-5.4")
    }

    @Test func incrementalReadDefaultsToCodexWithoutState() throws {
        // Without carrying state, incremental read loses model info
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("tc_codex_no_state_\(UUID().uuidString).jsonl")
        let chunk1 = """
        {"timestamp":"2026-04-11T10:00:00.000Z","type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5.4"}}
        {"timestamp":"2026-04-11T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}

        """
        try chunk1.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let result1 = try CodexLogParser.parseFile(at: tmpURL)

        // Append data without turn_context
        let chunk2 = """
        {"timestamp":"2026-04-11T10:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":80,"reasoning_output_tokens":0,"total_tokens":280}}}}

        """
        let fileHandle = try FileHandle(forWritingTo: tmpURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write(Data(chunk2.utf8))
        try fileHandle.close()

        // Without state carry-over, model defaults to "codex" — the old bug
        let result2 = try CodexLogParser.parseFile(at: tmpURL, fromOffset: result1.newOffset)
        #expect(result2.turns.count == 1)
        #expect(result2.turns[0].model == "codex")
    }

    // MARK: - Date parsing

    @Test func parsesISO8601WithFractionalSeconds() {
        let date = CodexLogParser.parseDate("2026-04-11T10:00:05.123Z")
        #expect(date != nil)
    }

    @Test func parsesISO8601WithoutFractionalSeconds() {
        let date = CodexLogParser.parseDate("2026-04-11T10:00:05Z")
        #expect(date != nil)
    }
}
