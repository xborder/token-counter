import Foundation
import SwiftData

@Model
final class PricingTier {
    /// Model identifier, e.g. "claude-opus-4-6".
    @Attribute(.unique) var model: String

    /// Provider: "claude" or "openai".
    var provider: String

    /// Price per 1M input tokens in USD.
    var inputPricePer1M: Double

    /// Price per 1M output tokens in USD.
    var outputPricePer1M: Double

    /// Price per 1M cache creation tokens in USD.
    var cacheCreationPricePer1M: Double

    /// Price per 1M cache read tokens in USD.
    var cacheReadPricePer1M: Double

    init(
        model: String,
        provider: String,
        inputPricePer1M: Double,
        outputPricePer1M: Double,
        cacheCreationPricePer1M: Double = 0,
        cacheReadPricePer1M: Double = 0
    ) {
        self.model = model
        self.provider = provider
        self.inputPricePer1M = inputPricePer1M
        self.outputPricePer1M = outputPricePer1M
        self.cacheCreationPricePer1M = cacheCreationPricePer1M
        self.cacheReadPricePer1M = cacheReadPricePer1M
    }
}

// MARK: - Bundled pricing loaded from pricing.json

struct PricingConfig: Codable {
    let models: [String: ModelPricing]

    struct ModelPricing: Codable {
        let provider: String
        let input: Double
        let output: Double
        let cacheCreation: Double
        let cacheRead: Double

        enum CodingKeys: String, CodingKey {
            case provider
            case input
            case output
            case cacheCreation = "cache_creation"
            case cacheRead = "cache_read"
        }
    }
}
