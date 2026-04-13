import Testing
import Foundation
@testable import TokenCounter

/// Integration tests verifying token counting and cost calculation invariants
/// across providers, aggregation methods, and display paths.
struct CostIntegrationTests {

    private func createTestStore() -> TokenStore {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_cost_test_\(UUID().uuidString).json")
        return TokenStore(storeURL: tmpURL)
    }

    private let calculator = CostCalculator()

    // MARK: - Cost breakdown rows sum to total

    @Test func breakdownRowsSumToEstimatedCost() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        // Claude turn with cache tokens
        let t1 = Turn(uuid: "t1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        t1.inputTokens = 50_000
        t1.outputTokens = 10_000
        t1.cacheCreationTokens = 20_000
        t1.cacheReadTokens = 100_000
        t1.estimatedCostUSD = calculator.cost(for: t1)
        store.insertTurn(t1, into: session)

        // Codex turn with reasoning tokens (output includes reasoning)
        let t2 = Turn(uuid: "t2", timestamp: Date(), model: "gpt-5.4", provider: "openai")
        t2.inputTokens = 30_000
        t2.outputTokens = 5_000  // includes 2000 reasoning
        t2.reasoningTokens = 2_000
        t2.cacheReadTokens = 10_000
        t2.estimatedCostUSD = calculator.cost(for: t2)
        store.insertTurn(t2, into: session)

        let repo = TokenUsageRepository(store: store)
        let summary = repo.summary(for: .allTime)

        // The displayed breakdown cost should sum to estimatedCost
        // UI shows: input + (output - reasoning) + cacheCreation + cacheRead + reasoning
        // Which equals: input + output + cacheCreation + cacheRead = estimatedCost
        let displayedSum = summary.inputCost
            + (summary.outputCost - summary.reasoningCost)
            + summary.cacheCreationCost
            + summary.cacheReadCost
            + summary.reasoningCost

        #expect(abs(displayedSum - summary.estimatedCost) < 0.0001,
                "Breakdown rows (\(displayedSum)) must sum to estimatedCost (\(summary.estimatedCost))")
    }

    // MARK: - Model breakdown costs sum to total

    @Test func modelBreakdownCostsSumToTotal() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        let models: [(String, String)] = [
            ("claude-opus-4-6", "claude"),
            ("claude-sonnet-4-6", "claude"),
            ("gpt-5.4", "openai"),
        ]
        for (i, (model, provider)) in models.enumerated() {
            let turn = Turn(uuid: "t\(i)", timestamp: Date(), model: model, provider: provider)
            turn.inputTokens = 10_000 * (i + 1)
            turn.outputTokens = 5_000 * (i + 1)
            turn.cacheCreationTokens = 1_000
            turn.cacheReadTokens = 2_000
            turn.estimatedCostUSD = calculator.cost(for: turn)
            store.insertTurn(turn, into: session)
        }

        let repo = TokenUsageRepository(store: store)
        let summary = repo.summary(for: .allTime)
        let breakdown = repo.modelBreakdown(for: .allTime)

        let breakdownCostSum = breakdown.reduce(0.0) { $0 + $1.estimatedCost }
        #expect(abs(breakdownCostSum - summary.estimatedCost) < 0.0001,
                "Model breakdown cost sum (\(breakdownCostSum)) must equal summary cost (\(summary.estimatedCost))")
    }

    // MARK: - Model breakdown tokens sum to total

    @Test func modelBreakdownTokensSumToTotal() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        let turn1 = Turn(uuid: "t1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn1.inputTokens = 10_000
        turn1.outputTokens = 5_000
        turn1.cacheCreationTokens = 3_000
        turn1.cacheReadTokens = 8_000
        turn1.estimatedCostUSD = calculator.cost(for: turn1)
        store.insertTurn(turn1, into: session)

        let turn2 = Turn(uuid: "t2", timestamp: Date(), model: "gpt-5.4", provider: "openai")
        turn2.inputTokens = 7_000
        turn2.outputTokens = 3_000
        turn2.reasoningTokens = 1_000
        turn2.cacheReadTokens = 2_000
        turn2.estimatedCostUSD = calculator.cost(for: turn2)
        store.insertTurn(turn2, into: session)

        let repo = TokenUsageRepository(store: store)
        let summary = repo.summary(for: .allTime)
        let breakdown = repo.modelBreakdown(for: .allTime)

        let breakdownInput = breakdown.reduce(0) { $0 + $1.inputTokens }
        let breakdownOutput = breakdown.reduce(0) { $0 + $1.outputTokens }
        let breakdownCacheCreate = breakdown.reduce(0) { $0 + $1.cacheCreationTokens }
        let breakdownCacheRead = breakdown.reduce(0) { $0 + $1.cacheReadTokens }
        let breakdownReasoning = breakdown.reduce(0) { $0 + $1.reasoningTokens }

        #expect(breakdownInput == summary.inputTokens)
        #expect(breakdownOutput == summary.outputTokens)
        #expect(breakdownCacheCreate == summary.cacheCreationTokens)
        #expect(breakdownCacheRead == summary.cacheReadTokens)
        #expect(breakdownReasoning == summary.reasoningTokens)
    }

    // MARK: - CostCalculator matches repository per-turn cost

    @Test func costCalculatorMatchesRepositoryPerTurnCost() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        let turn = Turn(uuid: "t1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.inputTokens = 50_000
        turn.outputTokens = 10_000
        turn.cacheCreationTokens = 20_000
        turn.cacheReadTokens = 100_000
        turn.estimatedCostUSD = calculator.cost(for: turn)
        store.insertTurn(turn, into: session)

        let repo = TokenUsageRepository(store: store)
        let summary = repo.summary(for: .allTime)

        // Repository recalculates cost; should match CostCalculator
        #expect(abs(summary.estimatedCost - turn.estimatedCostUSD) < 0.0001,
                "Repository cost (\(summary.estimatedCost)) must match CostCalculator (\(turn.estimatedCostUSD))")
    }

    // MARK: - Reasoning tokens not double-counted in cost

    @Test func reasoningTokensNotDoubleCountedInCost() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        // OpenAI turn where outputTokens includes reasoningTokens
        let turn = Turn(uuid: "t1", timestamp: Date(), model: "gpt-5.4", provider: "openai")
        turn.inputTokens = 10_000
        turn.outputTokens = 5_000  // includes 2000 reasoning
        turn.reasoningTokens = 2_000
        turn.estimatedCostUSD = calculator.cost(for: turn)
        store.insertTurn(turn, into: session)

        let repo = TokenUsageRepository(store: store)
        let summary = repo.summary(for: .allTime)

        let pricing = CostCalculator.bundledPricing["gpt-5.4"]!

        // Correct total: input cost + full output cost (which includes reasoning)
        // Reasoning is NOT added on top — it's a subset of outputCost
        let expectedCost = Double(10_000) * pricing.inputPricePer1M / 1_000_000
            + Double(5_000) * pricing.outputPricePer1M / 1_000_000

        #expect(abs(summary.estimatedCost - expectedCost) < 0.0001,
                "Cost should not double-count reasoning: got \(summary.estimatedCost), expected \(expectedCost)")

        // reasoningCost should be the reasoning portion of outputCost
        let expectedReasoningCost = Double(2_000) * pricing.outputPricePer1M / 1_000_000
        #expect(abs(summary.reasoningCost - expectedReasoningCost) < 0.0001)

        // output_displayed + reasoning_displayed = outputCost
        let outputDisplayed = summary.outputCost - summary.reasoningCost
        #expect(abs((outputDisplayed + summary.reasoningCost) - summary.outputCost) < 0.0001)
    }

    // MARK: - Cross-provider aggregation

    @Test func crossProviderAggregationIsConsistent() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        // Claude turn
        let t1 = Turn(uuid: "t1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        t1.inputTokens = 50_000
        t1.outputTokens = 10_000
        t1.cacheCreationTokens = 5_000
        t1.cacheReadTokens = 80_000
        t1.estimatedCostUSD = calculator.cost(for: t1)
        store.insertTurn(t1, into: session)

        // Codex turn with reasoning
        let t2 = Turn(uuid: "t2", timestamp: Date(), model: "gpt-5.4", provider: "openai")
        t2.inputTokens = 20_000
        t2.outputTokens = 8_000  // includes 3000 reasoning
        t2.reasoningTokens = 3_000
        t2.cacheReadTokens = 15_000
        t2.estimatedCostUSD = calculator.cost(for: t2)
        store.insertTurn(t2, into: session)

        let repo = TokenUsageRepository(store: store)

        // All providers
        let allSummary = repo.summary(for: .allTime, provider: .all)

        // Per-provider
        let claudeSummary = repo.summary(for: .allTime, provider: .claude)
        let openaiSummary = repo.summary(for: .allTime, provider: .openai)

        // Token counts should be additive across providers
        #expect(claudeSummary.inputTokens + openaiSummary.inputTokens == allSummary.inputTokens)
        #expect(claudeSummary.outputTokens + openaiSummary.outputTokens == allSummary.outputTokens)
        #expect(claudeSummary.cacheReadTokens + openaiSummary.cacheReadTokens == allSummary.cacheReadTokens)
        #expect(claudeSummary.cacheCreationTokens + openaiSummary.cacheCreationTokens == allSummary.cacheCreationTokens)
        #expect(claudeSummary.reasoningTokens + openaiSummary.reasoningTokens == allSummary.reasoningTokens)

        // Costs should be additive
        #expect(abs((claudeSummary.estimatedCost + openaiSummary.estimatedCost) - allSummary.estimatedCost) < 0.0001)
    }

    // MARK: - Unknown model distributes costs to breakdown

    @Test func unknownModelDistributesCostsToBreakdown() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        // Turn with unknown model — uses cached estimatedCostUSD
        let turn = Turn(uuid: "t1", timestamp: Date(), model: "unknown-future-model", provider: "claude")
        turn.inputTokens = 10_000
        turn.outputTokens = 5_000
        turn.estimatedCostUSD = 1.50  // pre-computed cost
        store.insertTurn(turn, into: session)

        let repo = TokenUsageRepository(store: store)
        let summary = repo.summary(for: .allTime)

        #expect(abs(summary.estimatedCost - 1.50) < 0.0001)

        // Per-type costs should sum to total (not leave breakdown empty)
        let typeCostSum = summary.inputCost + summary.outputCost
            + summary.cacheCreationCost + summary.cacheReadCost
        #expect(abs(typeCostSum - summary.estimatedCost) < 0.0001,
                "Unknown model per-type costs (\(typeCostSum)) must sum to total (\(summary.estimatedCost))")
    }

    // MARK: - Pi CLI token semantics

    @Test func piParserSubtractsCacheFromInput() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_pi_cache_\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // Pi JSONL with cached input tokens
        let content = """
        {"type":"message","id":"msg1","timestamp":"2026-04-10T10:00:00.000Z","message":{"role":"assistant","model":"gpt-5.4","provider":"openai","usage":{"input":5000,"output":200,"cacheRead":3000,"cacheWrite":0,"totalTokens":5200,"cost":{"total":0.015}}}}
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)

        let result = try PiLogParser.parseFile(at: tmpURL)
        #expect(result.turns.count == 1)

        let turn = result.turns[0]
        // input=5000 includes 3000 cached; non-cached = 5000 - 3000 = 2000
        #expect(turn.inputTokens == 2000, "Non-cached input should be input - cacheRead")
        #expect(turn.cacheReadTokens == 3000)
        // totalInputTokens = inputTokens + cacheReadTokens = 2000 + 3000 = 5000
        #expect(turn.inputTokens + turn.cacheReadTokens == 5000)
    }

    @Test func piParserHandlesZeroCacheRead() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_pi_no_cache_\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let content = """
        {"type":"message","id":"msg1","timestamp":"2026-04-10T10:00:00.000Z","message":{"role":"assistant","model":"gpt-5.4","provider":"openai","usage":{"input":4235,"output":240,"cacheRead":0,"cacheWrite":0,"totalTokens":4475,"cost":{"total":0.01419}}}}
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)

        let result = try PiLogParser.parseFile(at: tmpURL)
        let turn = result.turns[0]
        #expect(turn.inputTokens == 4235, "No cache → inputTokens = raw input")
        #expect(turn.cacheReadTokens == 0)
    }

    // MARK: - Input token consistency across providers

    @Test func inputTokenSemanticsConsistentAcrossProviders() {
        // For all providers: inputTokens = non-cached input only
        // totalInputTokens = inputTokens + cacheCreationTokens + cacheReadTokens

        // Claude: inputTokens directly from API (non-cached)
        let claude = Turn(uuid: "c1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        claude.inputTokens = 5000      // non-cached
        claude.cacheReadTokens = 3000  // cache read
        claude.cacheCreationTokens = 1000
        #expect(claude.totalInputTokens == 9000)

        // Codex: parser subtracts cached from raw
        let codex = Turn(uuid: "x1", timestamp: Date(), model: "gpt-5.4", provider: "openai")
        codex.inputTokens = 2000       // raw(5000) - cached(3000)
        codex.cacheReadTokens = 3000
        #expect(codex.totalInputTokens == 5000)

        // Cost formula treats inputTokens consistently
        let claudeCost = calculator.cost(for: claude)
        let codexCost = calculator.cost(for: codex)
        #expect(claudeCost > 0)
        #expect(codexCost > 0)

        // Verify the cost formula: input at input price, cache at cache price
        let claudePricing = CostCalculator.bundledPricing["claude-opus-4-6"]!
        let expectedClaudeCost = Double(5000) * claudePricing.inputPricePer1M / 1_000_000
            + Double(0) * claudePricing.outputPricePer1M / 1_000_000
            + Double(1000) * claudePricing.cacheCreationPricePer1M / 1_000_000
            + Double(3000) * claudePricing.cacheReadPricePer1M / 1_000_000
        #expect(abs(claudeCost - expectedClaudeCost) < 0.0001)
    }

    // MARK: - Provider filter completeness

    @Test func allProviderFiltersReturnCorrectSubsets() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        let providers: [(Provider, String)] = [
            (.claude, "claude-opus-4-6"),
            (.openai, "gpt-5.4"),
            (.pi, "gpt-5.4"),
            (.opencode, "gpt-5.4"),
        ]

        for (i, (provider, model)) in providers.enumerated() {
            let turn = Turn(uuid: "t\(i)", timestamp: Date(), model: model, provider: provider.rawValue)
            turn.inputTokens = 1000
            turn.outputTokens = 500
            turn.estimatedCostUSD = calculator.cost(for: turn)
            store.insertTurn(turn, into: session)
        }

        let repo = TokenUsageRepository(store: store)

        let allSummary = repo.summary(for: .allTime, provider: .all)
        #expect(allSummary.turnCount == 4)

        let claudeSummary = repo.summary(for: .allTime, provider: .claude)
        #expect(claudeSummary.turnCount == 1)

        let openaiSummary = repo.summary(for: .allTime, provider: .openai)
        #expect(openaiSummary.turnCount == 1)

        let piSummary = repo.summary(for: .allTime, provider: .pi)
        #expect(piSummary.turnCount == 1)

        let opencodeSummary = repo.summary(for: .allTime, provider: .opencode)
        #expect(opencodeSummary.turnCount == 1)

        // Sum of filtered should equal all
        let sumTurns = claudeSummary.turnCount + openaiSummary.turnCount
            + piSummary.turnCount + opencodeSummary.turnCount
        #expect(sumTurns == allSummary.turnCount)
    }

    // MARK: - Codex model state fixes mislabeled turns

    @Test func codexFileStateCarriesModelAcrossIncrementalReads() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_codex_state_\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // First chunk: turn_context sets model, followed by token_count
        let chunk1 = """
        {"timestamp":"2026-04-11T10:00:00.000Z","type":"session_meta","payload":{"id":"s1","cwd":"/Users/test/project"}}
        {"timestamp":"2026-04-11T10:00:01.000Z","type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5.4"}}
        {"timestamp":"2026-04-11T10:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}

        """
        try chunk1.write(to: tmpURL, atomically: true, encoding: .utf8)

        let result1 = try CodexLogParser.parseFile(at: tmpURL)
        #expect(result1.turns[0].model == "gpt-5.4")
        #expect(result1.fileState.model == "gpt-5.4")
        #expect(result1.fileState.cwd == "/Users/test/project")

        // Second chunk: only token_count, no turn_context
        let chunk2 = """
        {"timestamp":"2026-04-11T10:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":50,"output_tokens":80,"reasoning_output_tokens":20,"total_tokens":330}}}}

        """
        let fh = try FileHandle(forWritingTo: tmpURL)
        fh.seekToEndOfFile()
        fh.write(Data(chunk2.utf8))
        try fh.close()

        // With state: should carry over gpt-5.4
        let result2 = try CodexLogParser.parseFile(at: tmpURL, fromOffset: result1.newOffset, state: result1.fileState)
        #expect(result2.turns.count == 1)
        #expect(result2.turns[0].model == "gpt-5.4")
        #expect(result2.turns[0].cwd == "/Users/test/project")

        // Without state: falls back to "codex"
        let result3 = try CodexLogParser.parseFile(at: tmpURL, fromOffset: result1.newOffset)
        #expect(result3.turns[0].model == "codex")
    }

    // MARK: - CostCalculator formula covers all token types

    @Test func costCalculatorIncludesAllPricedTokenTypes() {
        let turn = Turn(uuid: "t1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.inputTokens = 10_000
        turn.outputTokens = 5_000
        turn.cacheCreationTokens = 3_000
        turn.cacheReadTokens = 20_000

        let cost = calculator.cost(for: turn)
        let pricing = CostCalculator.bundledPricing["claude-opus-4-6"]!

        let inputCost = Double(10_000) * pricing.inputPricePer1M / 1_000_000
        let outputCost = Double(5_000) * pricing.outputPricePer1M / 1_000_000
        let cacheCreateCost = Double(3_000) * pricing.cacheCreationPricePer1M / 1_000_000
        let cacheReadCost = Double(20_000) * pricing.cacheReadPricePer1M / 1_000_000
        let expected = inputCost + outputCost + cacheCreateCost + cacheReadCost

        #expect(abs(cost - expected) < 0.0001,
                "CostCalculator must price all token types: got \(cost), expected \(expected)")

        // Verify each component is non-zero
        #expect(inputCost > 0)
        #expect(outputCost > 0)
        #expect(cacheCreateCost > 0)
        #expect(cacheReadCost > 0)
    }

    // MARK: - TotalTokens consistency

    @Test func totalTokensEqualsInputPlusOutput() {
        let turn = Turn(uuid: "t1", timestamp: Date(), model: "gpt-5.4", provider: "openai")
        turn.inputTokens = 5_000
        turn.outputTokens = 3_000  // includes reasoning
        turn.reasoningTokens = 1_000
        turn.cacheCreationTokens = 2_000
        turn.cacheReadTokens = 8_000

        // totalInputTokens = inputTokens + cacheCreation + cacheRead = 5000 + 2000 + 8000 = 15000
        #expect(turn.totalInputTokens == 15_000)
        // totalTokens = totalInputTokens + outputTokens = 15000 + 3000 = 18000
        #expect(turn.totalTokens == 18_000)
    }

    // MARK: - Codex reasoning token pricing

    @Test func codexReasoningTokensPricedViaOutputTokens() {
        // For Codex/OpenAI: outputTokens includes reasoningTokens
        // CostCalculator prices outputTokens at outputPricePer1M
        // So reasoning tokens ARE priced (via output), not separately

        let turn = Turn(uuid: "t1", timestamp: Date(), model: "gpt-5.4", provider: "openai")
        turn.inputTokens = 10_000
        turn.outputTokens = 5_000  // includes 2000 reasoning
        turn.reasoningTokens = 2_000

        let pricing = CostCalculator.bundledPricing["gpt-5.4"]!
        let cost = calculator.cost(for: turn)

        // Cost should be for ALL 5000 output tokens (reasoning included)
        let expectedOutputCost = Double(5_000) * pricing.outputPricePer1M / 1_000_000
        let expectedInputCost = Double(10_000) * pricing.inputPricePer1M / 1_000_000
        #expect(abs(cost - (expectedInputCost + expectedOutputCost)) < 0.0001)

        // If reasoning were priced separately ON TOP of output, cost would be higher
        let wrongCost = expectedInputCost + expectedOutputCost
            + Double(2_000) * pricing.outputPricePer1M / 1_000_000
        #expect(cost < wrongCost, "Reasoning must not be double-counted in cost")
    }

    // MARK: - Mixed-provider summary with reasoning

    @Test func mixedProviderReasoningBreakdownIsCorrect() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        // Claude: no reasoning tokens
        let t1 = Turn(uuid: "t1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        t1.inputTokens = 10_000
        t1.outputTokens = 5_000
        t1.estimatedCostUSD = calculator.cost(for: t1)
        store.insertTurn(t1, into: session)

        // Codex: has reasoning tokens (included in output)
        let t2 = Turn(uuid: "t2", timestamp: Date(), model: "gpt-5.4", provider: "openai")
        t2.inputTokens = 10_000
        t2.outputTokens = 5_000
        t2.reasoningTokens = 2_000
        t2.estimatedCostUSD = calculator.cost(for: t2)
        store.insertTurn(t2, into: session)

        let repo = TokenUsageRepository(store: store)
        let summary = repo.summary(for: .allTime)

        // Output (non-reasoning) = total output - reasoning = 10000 - 2000 = 8000
        let nonReasoningOutput = summary.outputTokens - summary.reasoningTokens
        #expect(nonReasoningOutput == 8_000)
        #expect(summary.reasoningTokens == 2_000)

        // Cost invariant: displayed rows should sum to total
        let rowsSum = summary.inputCost
            + (summary.outputCost - summary.reasoningCost)
            + summary.cacheCreationCost + summary.cacheReadCost
            + summary.reasoningCost
        #expect(abs(rowsSum - summary.estimatedCost) < 0.0001)
    }

    // MARK: - Gpt-5.4, gpt-5.3-codex, gpt-5.2-codex pricing accuracy

    @Test func codexModelPricingIsAccurate() {
        // Verify each Codex model's pricing produces correct costs
        let testCases: [(model: String, inputPrice: Double, outputPrice: Double)] = [
            ("gpt-5.4", 2.50, 15.0),
            ("gpt-5.3-codex", 1.75, 14.0),
            ("gpt-5.2-codex", 1.75, 14.0),
        ]

        for tc in testCases {
            let turn = Turn(uuid: "t-\(tc.model)", timestamp: Date(), model: tc.model, provider: "openai")
            turn.inputTokens = 1_000_000
            turn.outputTokens = 1_000_000

            let cost = calculator.cost(for: turn)
            let expected = tc.inputPrice + tc.outputPrice
            #expect(abs(cost - expected) < 0.001,
                    "\(tc.model): expected $\(expected), got $\(cost)")
        }
    }

    // MARK: - Cache savings calculation

    @Test func cacheSavingsCalculatedCorrectly() {
        let store = createTestStore()
        let project = store.findOrCreateProject(path: "-test-project")
        let session = store.findOrCreateSession(sessionId: "s1", in: project, firstTurn: nil)

        let turn = Turn(uuid: "t1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.inputTokens = 10_000
        turn.outputTokens = 5_000
        turn.cacheReadTokens = 100_000  // Would have been $1.50 full price, but $0.15 at cache rate
        turn.estimatedCostUSD = calculator.cost(for: turn)
        store.insertTurn(turn, into: session)

        let repo = TokenUsageRepository(store: store)
        let summary = repo.summary(for: .allTime)

        let pricing = CostCalculator.bundledPricing["claude-opus-4-6"]!
        let expectedSavings = Double(100_000) * (pricing.inputPricePer1M - pricing.cacheReadPricePer1M) / 1_000_000
        #expect(abs(summary.cacheSavings - expectedSavings) < 0.0001)
        #expect(summary.cacheSavings > 0)
    }
}
