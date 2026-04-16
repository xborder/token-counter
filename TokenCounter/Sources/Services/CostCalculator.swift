import Foundation

/// Calculates estimated costs for token usage based on per-model pricing.
struct CostCalculator {

    /// Bundled pricing: model identifier -> pricing info.
    /// Prices are per 1M tokens in USD.
    struct ModelPricing {
        let inputPricePer1M: Double
        let outputPricePer1M: Double
        let cacheCreationPricePer1M: Double
        let cacheReadPricePer1M: Double
        let cacheCreation1hPricePer1M: Double

        init(
            inputPricePer1M: Double,
            outputPricePer1M: Double,
            cacheCreationPricePer1M: Double,
            cacheReadPricePer1M: Double,
            cacheCreation1hPricePer1M: Double? = nil
        ) {
            self.inputPricePer1M = inputPricePer1M
            self.outputPricePer1M = outputPricePer1M
            self.cacheCreationPricePer1M = cacheCreationPricePer1M
            self.cacheReadPricePer1M = cacheReadPricePer1M
            self.cacheCreation1hPricePer1M = cacheCreation1hPricePer1M ?? cacheCreationPricePer1M
        }
    }

    struct CostBreakdown {
        let input: Double
        let output: Double
        let cacheCreation: Double
        let cacheRead: Double
        let reasoning: Double

        var total: Double {
            input + output + cacheCreation + cacheRead
        }
    }

    /// Default bundled pricing for known models.
    static let bundledPricing: [String: ModelPricing] = loadBundledPricing()

    /// User overrides loaded from settings (model -> pricing).
    var userOverrides: [String: ModelPricing] = [:]

    private static func loadBundledPricing() -> [String: ModelPricing] {
        guard let url = Bundle.module.url(forResource: "pricing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(PricingConfig.self, from: data) else {
            assertionFailure("Unable to load bundled pricing.json")
            return [:]
        }

        return config.models.reduce(into: [:]) { result, entry in
            result[entry.key] = ModelPricing(
                inputPricePer1M: entry.value.input,
                outputPricePer1M: entry.value.output,
                cacheCreationPricePer1M: entry.value.cacheCreation,
                cacheReadPricePer1M: entry.value.cacheRead,
                cacheCreation1hPricePer1M: entry.value.cacheCreation1h
            )
        }
    }

    /// Look up pricing for a model, checking user overrides first, then bundled.
    func pricing(for model: String) -> ModelPricing? {
        if let override = userOverrides[model] {
            return override
        }
        if let bundled = Self.bundledPricing[model] {
            return bundled
        }
        // Try prefix matching for model variants (e.g. "claude-opus-4-6-20260410")
        for (key, value) in Self.bundledPricing {
            if model.hasPrefix(key) {
                return value
            }
        }
        return nil
    }

    func costBreakdown(for turn: Turn) -> CostBreakdown? {
        guard let pricing = pricing(for: turn.model) else { return nil }

        let inputCost = Double(turn.inputTokens) * pricing.inputPricePer1M / 1_000_000.0
        let outputCost = Double(turn.outputTokens) * pricing.outputPricePer1M / 1_000_000.0
        let cacheCreateCost = cacheCreationCost(for: turn, pricing: pricing)
        let cacheReadCost = Double(turn.cacheReadTokens) * pricing.cacheReadPricePer1M / 1_000_000.0
        let reasoningCost = Double(turn.reasoningTokens) * pricing.outputPricePer1M / 1_000_000.0

        return CostBreakdown(
            input: inputCost,
            output: outputCost,
            cacheCreation: cacheCreateCost,
            cacheRead: cacheReadCost,
            reasoning: reasoningCost
        )
    }

    /// Calculate the cost in USD for a single turn.
    func cost(for turn: Turn) -> Double {
        costBreakdown(for: turn)?.total ?? 0
    }

    /// Calculate how much money was saved by cache hits vs full-price input.
    func cacheSavings(for turn: Turn) -> Double {
        guard let pricing = pricing(for: turn.model) else { return 0 }

        let fullPriceCost = Double(turn.cacheReadTokens) * pricing.inputPricePer1M / 1_000_000.0
        let actualCost = Double(turn.cacheReadTokens) * pricing.cacheReadPricePer1M / 1_000_000.0

        return fullPriceCost - actualCost
    }

    /// Assign costs to all turns in a batch.
    func assignCosts(to turns: [Turn]) {
        for turn in turns {
            turn.estimatedCostUSD = cost(for: turn)
        }
    }

    private func cacheCreationCost(for turn: Turn, pricing: ModelPricing) -> Double {
        let classifiedTokens = turn.cacheCreation5mTokens + turn.cacheCreation1hTokens
        if classifiedTokens == 0 {
            return Double(turn.cacheCreationTokens) * pricing.cacheCreationPricePer1M / 1_000_000.0
        }

        let unclassifiedTokens = max(0, turn.cacheCreationTokens - classifiedTokens)
        let fiveMinuteTokens = turn.cacheCreation5mTokens + unclassifiedTokens

        return Double(fiveMinuteTokens) * pricing.cacheCreationPricePer1M / 1_000_000.0
            + Double(turn.cacheCreation1hTokens) * pricing.cacheCreation1hPricePer1M / 1_000_000.0
    }
}
