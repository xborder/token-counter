import XCTest
@testable import TokenCounter

final class CostCalculatorTests: XCTestCase {

    var calculator: CostCalculator!

    override func setUp() {
        super.setUp()
        calculator = CostCalculator()
    }

    // MARK: - Basic cost calculation

    func testOpusCostCalculation() {
        let turn = Turn(uuid: "test1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.inputTokens = 1_000_000   // 1M tokens
        turn.outputTokens = 100_000    // 100K tokens
        turn.cacheCreationTokens = 0
        turn.cacheReadTokens = 0

        let cost = calculator.cost(for: turn)

        // input: 1M * $15/1M = $15.00
        // output: 100K * $75/1M = $7.50
        XCTAssertEqual(cost, 22.5, accuracy: 0.001)
    }

    func testHaikuCostCalculation() {
        let turn = Turn(uuid: "test2", timestamp: Date(), model: "claude-haiku-4-5-20251001", provider: "claude")
        turn.inputTokens = 1_000_000
        turn.outputTokens = 100_000

        let cost = calculator.cost(for: turn)

        // input: 1M * $0.80/1M = $0.80
        // output: 100K * $4.00/1M = $0.40
        XCTAssertEqual(cost, 1.2, accuracy: 0.001)
    }

    // MARK: - Cache cost calculation

    func testCacheCreationCost() {
        let turn = Turn(uuid: "test3", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.inputTokens = 100
        turn.outputTokens = 50
        turn.cacheCreationTokens = 10_000
        turn.cacheReadTokens = 0

        let cost = calculator.cost(for: turn)

        // input: 100 * $15/1M = $0.0015
        // output: 50 * $75/1M = $0.00375
        // cache create: 10K * $18.75/1M = $0.1875
        let expected = 0.0015 + 0.00375 + 0.1875
        XCTAssertEqual(cost, expected, accuracy: 0.0001)
    }

    func testCacheReadCost() {
        let turn = Turn(uuid: "test4", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.inputTokens = 100
        turn.outputTokens = 50
        turn.cacheCreationTokens = 0
        turn.cacheReadTokens = 10_000

        let cost = calculator.cost(for: turn)

        // input: 100 * $15/1M = $0.0015
        // output: 50 * $75/1M = $0.00375
        // cache read: 10K * $1.50/1M = $0.015
        let expected = 0.0015 + 0.00375 + 0.015
        XCTAssertEqual(cost, expected, accuracy: 0.0001)
    }

    // MARK: - Cache savings calculation

    func testCacheSavingsCalculation() {
        let turn = Turn(uuid: "test5", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.cacheReadTokens = 1_000_000  // 1M tokens read from cache

        let savings = calculator.cacheSavings(for: turn)

        // Full price: 1M * $15/1M = $15.00
        // Cache read price: 1M * $1.50/1M = $1.50
        // Savings: $15.00 - $1.50 = $13.50
        XCTAssertEqual(savings, 13.50, accuracy: 0.001)
    }

    func testNoCacheSavingsWhenNoCacheRead() {
        let turn = Turn(uuid: "test6", timestamp: Date(), model: "claude-opus-4-6", provider: "claude")
        turn.cacheReadTokens = 0

        let savings = calculator.cacheSavings(for: turn)
        XCTAssertEqual(savings, 0)
    }

    // MARK: - Unknown model

    func testUnknownModelReturnsZero() {
        let turn = Turn(uuid: "test7", timestamp: Date(), model: "unknown-model-xyz", provider: "claude")
        turn.inputTokens = 1000
        turn.outputTokens = 500

        let cost = calculator.cost(for: turn)
        XCTAssertEqual(cost, 0, "Unknown model should return zero cost")
    }

    // MARK: - Model prefix matching

    func testModelPrefixMatching() {
        let turn = Turn(uuid: "test8", timestamp: Date(), model: "claude-opus-4-6-20260410", provider: "claude")
        turn.inputTokens = 1_000_000
        turn.outputTokens = 0

        let cost = calculator.cost(for: turn)
        XCTAssertEqual(cost, 15.0, accuracy: 0.001, "Should match claude-opus-4-6 via prefix")
    }

    // MARK: - OpenAI model pricing

    func testO3CostCalculation() {
        let turn = Turn(uuid: "test9", timestamp: Date(), model: "o3", provider: "openai")
        turn.inputTokens = 1_000_000
        turn.outputTokens = 100_000

        let cost = calculator.cost(for: turn)

        // input: 1M * $2/1M = $2.00
        // output: 100K * $8/1M = $0.80
        XCTAssertEqual(cost, 2.80, accuracy: 0.001)
    }

    // MARK: - Batch cost assignment

    func testAssignCosts() {
        let turns = [
            Turn(uuid: "batch1", timestamp: Date(), model: "claude-opus-4-6", provider: "claude"),
            Turn(uuid: "batch2", timestamp: Date(), model: "claude-haiku-4-5-20251001", provider: "claude"),
        ]
        turns[0].inputTokens = 1000
        turns[0].outputTokens = 500
        turns[1].inputTokens = 2000
        turns[1].outputTokens = 1000

        calculator.assignCosts(to: turns)

        XCTAssertGreaterThan(turns[0].estimatedCostUSD, 0)
        XCTAssertGreaterThan(turns[1].estimatedCostUSD, 0)
        XCTAssertGreaterThan(turns[0].estimatedCostUSD, turns[1].estimatedCostUSD,
            "Opus should cost more than Haiku for similar token counts")
    }

    // MARK: - User overrides

    func testUserOverridePricing() {
        var calculator = CostCalculator()
        calculator.userOverrides["custom-model"] = CostCalculator.ModelPricing(
            inputPricePer1M: 10.0,
            outputPricePer1M: 50.0,
            cacheCreationPricePer1M: 0,
            cacheReadPricePer1M: 0
        )

        let turn = Turn(uuid: "override1", timestamp: Date(), model: "custom-model", provider: "claude")
        turn.inputTokens = 1_000_000
        turn.outputTokens = 100_000

        let cost = calculator.cost(for: turn)
        XCTAssertEqual(cost, 15.0, accuracy: 0.001) // $10 input + $5 output
    }
}
