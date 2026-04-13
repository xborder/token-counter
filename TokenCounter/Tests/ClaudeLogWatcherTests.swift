import Testing
import Foundation
@testable import TokenCounter

struct ClaudeLogWatcherTests {

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 7_000_000_000,
        pollNanoseconds: UInt64 = 100_000_000,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return condition()
    }

    @Test func updatesExistingTurnWhenLaterStreamingChunkArrives() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tc_claude_watch_\(UUID().uuidString)", isDirectory: true)
        let projectDir = root.appendingPathComponent("test-project", isDirectory: true)
        let logURL = projectDir.appendingPathComponent("session-1.jsonl")
        let storeURL = root.appendingPathComponent("store.json")

        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let initialChunk = """
        {"parentUuid":"user-001","isSidechain":false,"message":{"model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":50}},"requestId":"req_live","type":"assistant","uuid":"assist-001a","timestamp":"2026-04-11T11:42:10.000Z","sessionId":"session-1"}
        """
        try initialChunk.write(to: logURL, atomically: true, encoding: .utf8)

        let store = TokenStore(storeURL: storeURL)
        let watcher = ClaudeLogWatcher(basePath: root.path)
        watcher.start(store: store)
        defer { watcher.stop() }

        #expect(await waitUntil {
            store.turn(uuid: "req_live")?.outputTokens == 50
        })

        let finalChunk = """
        {"parentUuid":"user-001","isSidechain":false,"message":{"model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":800,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":150}},"requestId":"req_live","type":"assistant","uuid":"assist-001b","timestamp":"2026-04-11T11:42:11.000Z","sessionId":"session-1"}
        """
        let fileHandle = try FileHandle(forWritingTo: logURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write(Data(finalChunk.utf8))
        try fileHandle.close()

        #expect(await waitUntil {
            guard let turn = store.turn(uuid: "req_live") else { return false }
            return turn.outputTokens == 150 && turn.cacheReadTokens == 800
        })

        let turn = try #require(store.turn(uuid: "req_live"))
        let expectedCost = CostCalculator().cost(for: turn)
        #expect(abs(turn.estimatedCostUSD - expectedCost) < 0.0001)
    }
}
