import Foundation

/// Central repository for querying aggregated token usage data.
/// Provides filtered and grouped queries for ViewModels.
final class TokenUsageRepository {

    private var store: TokenStore

    init(store: TokenStore) {
        self.store = store
    }

    // MARK: - Time range

    enum TimeRange: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "7d"
        case month = "30d"
        case allTime = "All Time"

        var id: String { rawValue }

        var startDate: Date? {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .today:
                return calendar.startOfDay(for: now)
            case .week:
                return calendar.date(byAdding: .day, value: -7, to: now)
            case .month:
                return calendar.date(byAdding: .day, value: -30, to: now)
            case .allTime:
                return nil
            }
        }
    }

    // MARK: - Provider filter

    enum ProviderFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case claude = "Claude"
        case openai = "OpenAI"
        case pi = "Pi CLI"
        case opencode = "OpenCode"

        var id: String { rawValue }
    }

    // MARK: - Aggregated stats

    struct UsageSummary {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
        var reasoningTokens: Int = 0
        var cachedPromptTokens: Int = 0
        var totalTokens: Int = 0
        var estimatedCost: Double = 0
        var cacheSavings: Double = 0
        var turnCount: Int = 0

        // Per-type cost breakdown
        var inputCost: Double = 0
        var outputCost: Double = 0
        var cacheCreationCost: Double = 0
        var cacheReadCost: Double = 0
        var reasoningCost: Double = 0
    }

    struct ModelUsage: Identifiable {
        let model: String
        let provider: String
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
        var reasoningTokens: Int = 0
        var cachedPromptTokens: Int = 0
        var totalTokens: Int = 0
        var estimatedCost: Double = 0
        var turnCount: Int = 0

        var id: String { model }
    }

    /// Fetch overall usage summary for a time range and optional provider filter.
    func summary(for timeRange: TimeRange, provider: ProviderFilter = .all) -> UsageSummary {
        let turns = fetchTurns(for: timeRange, provider: provider)
        let calculator = CostCalculator()

        var summary = UsageSummary()
        for turn in turns {
            summary.inputTokens += turn.inputTokens
            summary.outputTokens += turn.outputTokens
            summary.cacheCreationTokens += turn.cacheCreationTokens
            summary.cacheReadTokens += turn.cacheReadTokens
            summary.reasoningTokens += turn.reasoningTokens
            summary.cachedPromptTokens += turn.cachedPromptTokens
            summary.totalTokens += turn.totalTokens
            summary.cacheSavings += calculator.cacheSavings(for: turn)
            summary.turnCount += 1

            if let pricing = calculator.pricing(for: turn.model) {
                let inputCost = Double(turn.inputTokens) * pricing.inputPricePer1M / 1_000_000
                let outputCost = Double(turn.outputTokens) * pricing.outputPricePer1M / 1_000_000
                let cacheCreationCost = Double(turn.cacheCreationTokens) * pricing.cacheCreationPricePer1M / 1_000_000
                let cacheReadCost = Double(turn.cacheReadTokens) * pricing.cacheReadPricePer1M / 1_000_000
                summary.inputCost += inputCost
                summary.outputCost += outputCost
                summary.cacheCreationCost += cacheCreationCost
                summary.cacheReadCost += cacheReadCost
                summary.reasoningCost += Double(turn.reasoningTokens) * pricing.outputPricePer1M / 1_000_000
                summary.estimatedCost += inputCost + outputCost + cacheCreationCost + cacheReadCost
            } else {
                summary.estimatedCost += turn.estimatedCostUSD
            }
        }
        return summary
    }

    /// Fetch per-model usage breakdown for a time range and optional provider filter.
    func modelBreakdown(for timeRange: TimeRange, provider: ProviderFilter = .all) -> [ModelUsage] {
        let turns = fetchTurns(for: timeRange, provider: provider)
        let calculator = CostCalculator()
        var byModel: [String: ModelUsage] = [:]

        for turn in turns {
            var usage = byModel[turn.model] ?? ModelUsage(model: turn.model, provider: turn.provider)
            usage.inputTokens += turn.inputTokens
            usage.outputTokens += turn.outputTokens
            usage.cacheCreationTokens += turn.cacheCreationTokens
            usage.cacheReadTokens += turn.cacheReadTokens
            usage.reasoningTokens += turn.reasoningTokens
            usage.cachedPromptTokens += turn.cachedPromptTokens
            usage.totalTokens += turn.totalTokens
            if let pricing = calculator.pricing(for: turn.model) {
                usage.estimatedCost += Double(turn.inputTokens) * pricing.inputPricePer1M / 1_000_000
                    + Double(turn.outputTokens) * pricing.outputPricePer1M / 1_000_000
                    + Double(turn.cacheCreationTokens) * pricing.cacheCreationPricePer1M / 1_000_000
                    + Double(turn.cacheReadTokens) * pricing.cacheReadPricePer1M / 1_000_000
            } else {
                usage.estimatedCost += turn.estimatedCostUSD
            }
            usage.turnCount += 1
            byModel[turn.model] = usage
        }

        return byModel.values.sorted { $0.estimatedCost > $1.estimatedCost }
    }

    /// Fetch projects that have at least one session active within the time range.
    func projects(for timeRange: TimeRange) -> [Project] {
        let startDate = timeRange.startDate
        return store.projects.values
            .filter { project in
                guard let startDate else { return !project.sessions.isEmpty }
                return project.sessions.contains { $0.lastActivityAt >= startDate }
            }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Fetch sessions for a project, filtered by time range.
    func sessions(for project: Project, timeRange: TimeRange) -> [Session] {
        let startDate = timeRange.startDate
        return project.sessions
            .filter { session in
                guard let startDate else { return true }
                return session.lastActivityAt >= startDate
            }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Fetch turns for a session, optionally filtered by time range.
    func turns(for session: Session, timeRange: TimeRange = .allTime) -> [Turn] {
        let startDate = timeRange.startDate
        return session.turns
            .filter { startDate == nil || $0.timestamp >= startDate! }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private

    private func fetchTurns(for timeRange: TimeRange, provider: ProviderFilter = .all) -> [Turn] {
        var turns = store.allTurns
        if let startDate = timeRange.startDate {
            turns = turns.filter { $0.timestamp >= startDate }
        }
        switch provider {
        case .all:
            return turns
        case .claude:
            return turns.filter { $0.provider == Provider.claude.rawValue }
        case .openai:
            return turns.filter { $0.provider == Provider.openai.rawValue }
        case .pi:
            return turns.filter { $0.provider == Provider.pi.rawValue }
        case .opencode:
            return turns.filter { $0.provider == Provider.opencode.rawValue }
        }
    }
}
