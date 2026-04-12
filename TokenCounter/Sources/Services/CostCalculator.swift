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
    }

    /// Default bundled pricing for known models.
    static let bundledPricing: [String: ModelPricing] = [
        // Claude models
        "claude-opus-4-6": ModelPricing(
            inputPricePer1M: 15.0,
            outputPricePer1M: 75.0,
            cacheCreationPricePer1M: 18.75,
            cacheReadPricePer1M: 1.50
        ),
        "claude-sonnet-4-6": ModelPricing(
            inputPricePer1M: 3.0,
            outputPricePer1M: 15.0,
            cacheCreationPricePer1M: 3.75,
            cacheReadPricePer1M: 0.30
        ),
        "claude-haiku-4-5-20251001": ModelPricing(
            inputPricePer1M: 0.80,
            outputPricePer1M: 4.0,
            cacheCreationPricePer1M: 1.0,
            cacheReadPricePer1M: 0.08
        ),
        // OpenAI models
        "o3": ModelPricing(
            inputPricePer1M: 2.0,
            outputPricePer1M: 8.0,
            cacheCreationPricePer1M: 0,
            cacheReadPricePer1M: 0
        ),
        "o4-mini": ModelPricing(
            inputPricePer1M: 1.10,
            outputPricePer1M: 4.40,
            cacheCreationPricePer1M: 0,
            cacheReadPricePer1M: 0
        ),
        "gpt-4o": ModelPricing(
            inputPricePer1M: 2.50,
            outputPricePer1M: 10.0,
            cacheCreationPricePer1M: 0,
            cacheReadPricePer1M: 1.25
        ),
        "gpt-4o-mini": ModelPricing(
            inputPricePer1M: 0.15,
            outputPricePer1M: 0.60,
            cacheCreationPricePer1M: 0,
            cacheReadPricePer1M: 0.075
        ),
        // Codex CLI models
        "codex": ModelPricing(
            inputPricePer1M: 2.50,
            outputPricePer1M: 10.0,
            cacheCreationPricePer1M: 0,
            cacheReadPricePer1M: 1.25
        ),
        "codex-mini": ModelPricing(
            inputPricePer1M: 0.15,
            outputPricePer1M: 0.60,
            cacheCreationPricePer1M: 0,
            cacheReadPricePer1M: 0.075
        ),
        "gpt-5.4": ModelPricing(
            inputPricePer1M: 2.50,
            outputPricePer1M: 10.0,
            cacheCreationPricePer1M: 0,
            cacheReadPricePer1M: 1.25
        ),
        "gpt-5.3-codex": ModelPricing(
            inputPricePer1M: 2.50,
            outputPricePer1M: 10.0,
            cacheCreationPricePer1M: 0,
            cacheReadPricePer1M: 1.25
        ),
    ]

    /// User overrides loaded from settings (model -> pricing).
    var userOverrides: [String: ModelPricing] = [:]

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

    /// Calculate the cost in USD for a single turn.
    func cost(for turn: Turn) -> Double {
        guard let pricing = pricing(for: turn.model) else { return 0 }

        let inputCost = Double(turn.inputTokens) * pricing.inputPricePer1M / 1_000_000.0
        let outputCost = Double(turn.outputTokens) * pricing.outputPricePer1M / 1_000_000.0
        let cacheCreateCost = Double(turn.cacheCreationTokens) * pricing.cacheCreationPricePer1M / 1_000_000.0
        let cacheReadCost = Double(turn.cacheReadTokens) * pricing.cacheReadPricePer1M / 1_000_000.0

        return inputCost + outputCost + cacheCreateCost + cacheReadCost
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
}
