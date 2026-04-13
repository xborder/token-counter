import Testing
import Foundation
@testable import TokenCounter

struct CostCalculatorTests {

    private let calculator = CostCalculator()

    // MARK: - Basic cost calculation

    @Test func opusCostCalculation() {
        let turn = Turn(uuid: "t1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.inputTokens = 1_000_000
        turn.outputTokens = 100_000
        // $5.00 input + $2.50 output = $7.50
        #expect(abs(calculator.cost(for: turn) - 7.5) < 0.001)
    }

    @Test func haikuCostCalculation() {
        let turn = Turn(uuid: "t2", timestamp: Date(), model: "claude-haiku-4-5-20251001", provider: "claude")
        turn.inputTokens = 1_000_000
        turn.outputTokens = 100_000
        // $1.00 + $0.50 = $1.50
        #expect(abs(calculator.cost(for: turn) - 1.5) < 0.001)
    }

    // MARK: - Cache cost calculation

    @Test func cacheCreationCost() {
        let turn = Turn(uuid: "t3", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.inputTokens = 100
        turn.outputTokens = 50
        turn.cacheCreationTokens = 10_000
        let expected = 0.0005 + 0.00125 + 0.0625
        #expect(abs(calculator.cost(for: turn) - expected) < 0.0001)
    }

    @Test func cacheReadCost() {
        let turn = Turn(uuid: "t4", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.inputTokens = 100
        turn.outputTokens = 50
        turn.cacheReadTokens = 10_000
        let expected = 0.0005 + 0.00125 + 0.005
        #expect(abs(calculator.cost(for: turn) - expected) < 0.0001)
    }

    @Test func cacheCreationUsesTTLPricing() {
        let turn = Turn(uuid: "t4b", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.cacheCreationTokens = 30_000
        turn.cacheCreation5mTokens = 10_000
        turn.cacheCreation1hTokens = 20_000

        let expected = 0.0625 + 0.2
        #expect(abs(calculator.cost(for: turn) - expected) < 0.0001)
    }

    // MARK: - Cache savings

    @Test func cacheSavingsCalculation() {
        let turn = Turn(uuid: "t5", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.cacheReadTokens = 1_000_000
        // Full: $5.00, Cache read: $0.50, Savings: $4.50
        #expect(abs(calculator.cacheSavings(for: turn) - 4.5) < 0.001)
    }

    @Test func noCacheSavingsWhenNoCacheRead() {
        let turn = Turn(uuid: "t6", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        #expect(calculator.cacheSavings(for: turn) == 0)
    }

    // MARK: - Unknown model

    @Test func unknownModelReturnsZero() {
        let turn = Turn(uuid: "t7", timestamp: Date(), model: "unknown-model-xyz", provider: "claude")
        turn.inputTokens = 1000
        turn.outputTokens = 500
        #expect(calculator.cost(for: turn) == 0)
    }

    // MARK: - Prefix matching

    @Test func modelPrefixMatching() {
        let turn = Turn(uuid: "t8", timestamp: Date(), model: "claude-opus-4-6-20260410", provider: "claude")
        turn.inputTokens = 1_000_000
        #expect(abs(calculator.cost(for: turn) - 5.0) < 0.001)
    }

    // MARK: - OpenAI

    @Test func o3CostCalculation() {
        let turn = Turn(uuid: "t9", timestamp: Date(), model: "o3", provider: "openai")
        turn.inputTokens = 1_000_000
        turn.outputTokens = 100_000
        // $2.00 + $0.80 = $2.80
        #expect(abs(calculator.cost(for: turn) - 2.80) < 0.001)
    }

    // MARK: - Batch assignment

    @Test func assignCosts() {
        let turns = [
            Turn(uuid: "b1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude"),
            Turn(uuid: "b2", timestamp: Date(), model: "claude-haiku-4-5-20251001", provider: "claude"),
        ]
        turns[0].inputTokens = 1000; turns[0].outputTokens = 500
        turns[1].inputTokens = 2000; turns[1].outputTokens = 1000
        calculator.assignCosts(to: turns)
        #expect(turns[0].estimatedCostUSD > 0)
        #expect(turns[1].estimatedCostUSD > 0)
        #expect(turns[0].estimatedCostUSD > turns[1].estimatedCostUSD)
    }

    // MARK: - User overrides

    @Test func userOverridePricing() {
        var calc = CostCalculator()
        calc.userOverrides["custom-model"] = CostCalculator.ModelPricing(
            inputPricePer1M: 10.0, outputPricePer1M: 50.0,
            cacheCreationPricePer1M: 0, cacheReadPricePer1M: 0
        )
        let turn = Turn(uuid: "o1", timestamp: Date(), model: "custom-model", provider: "claude")
        turn.inputTokens = 1_000_000
        turn.outputTokens = 100_000
        // $10 + $5 = $15
        #expect(abs(calc.cost(for: turn) - 15.0) < 0.001)
    }

    @Test func bundledPricingMatchesCurrentProviderDocs() throws {
        let opus = try #require(CostCalculator.bundledPricing["claude-opus-4-6"])
        #expect(opus.inputPricePer1M == 5.0)
        #expect(opus.outputPricePer1M == 25.0)
        #expect(opus.cacheCreationPricePer1M == 6.25)
        #expect(opus.cacheCreation1hPricePer1M == 10.0)
        #expect(opus.cacheReadPricePer1M == 0.5)

        let o3 = try #require(CostCalculator.bundledPricing["o3"])
        #expect(o3.inputPricePer1M == 2.0)
        #expect(o3.outputPricePer1M == 8.0)
        #expect(o3.cacheReadPricePer1M == 0.5)

        let o4Mini = try #require(CostCalculator.bundledPricing["o4-mini"])
        #expect(o4Mini.inputPricePer1M == 1.10)
        #expect(o4Mini.outputPricePer1M == 4.40)
        #expect(o4Mini.cacheReadPricePer1M == 0.275)

        let gpt54 = try #require(CostCalculator.bundledPricing["gpt-5.4"])
        #expect(gpt54.inputPricePer1M == 2.50)
        #expect(gpt54.outputPricePer1M == 15.0)
        #expect(gpt54.cacheReadPricePer1M == 0.25)

        let gpt53Codex = try #require(CostCalculator.bundledPricing["gpt-5.3-codex"])
        #expect(gpt53Codex.inputPricePer1M == 1.75)
        #expect(gpt53Codex.outputPricePer1M == 14.0)
        #expect(gpt53Codex.cacheReadPricePer1M == 0.175)
    }
}
