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

    // MARK: - Aggregated stats

    struct UsageSummary {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
        var totalTokens: Int = 0
        var estimatedCost: Double = 0
        var cacheSavings: Double = 0
        var turnCount: Int = 0
    }

    struct ModelUsage: Identifiable {
        let model: String
        let provider: String
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
        var totalTokens: Int = 0
        var estimatedCost: Double = 0
        var turnCount: Int = 0

        var id: String { model }
    }

    /// Fetch overall usage summary for a time range.
    func summary(for timeRange: TimeRange) -> UsageSummary {
        let turns = fetchTurns(for: timeRange)
        let calculator = CostCalculator()

        var summary = UsageSummary()
        for turn in turns {
            summary.inputTokens += turn.inputTokens
            summary.outputTokens += turn.outputTokens
            summary.cacheCreationTokens += turn.cacheCreationTokens
            summary.cacheReadTokens += turn.cacheReadTokens
            summary.totalTokens += turn.totalTokens
            summary.estimatedCost += turn.estimatedCostUSD
            summary.cacheSavings += calculator.cacheSavings(for: turn)
            summary.turnCount += 1
        }
        return summary
    }

    /// Fetch per-model usage breakdown for a time range.
    func modelBreakdown(for timeRange: TimeRange) -> [ModelUsage] {
        let turns = fetchTurns(for: timeRange)
        var byModel: [String: ModelUsage] = [:]

        for turn in turns {
            var usage = byModel[turn.model] ?? ModelUsage(model: turn.model, provider: turn.provider)
            usage.inputTokens += turn.inputTokens
            usage.outputTokens += turn.outputTokens
            usage.cacheCreationTokens += turn.cacheCreationTokens
            usage.cacheReadTokens += turn.cacheReadTokens
            usage.totalTokens += turn.totalTokens
            usage.estimatedCost += turn.estimatedCostUSD
            usage.turnCount += 1
            byModel[turn.model] = usage
        }

        return byModel.values.sorted { $0.estimatedCost > $1.estimatedCost }
    }

    /// Fetch all projects with their sessions.
    func projects(for timeRange: TimeRange) -> [Project] {
        store.projects.values.sorted { $0.displayName < $1.displayName }
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

    /// Fetch turns for a session.
    func turns(for session: Session) -> [Turn] {
        session.turns.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private

    private func fetchTurns(for timeRange: TimeRange) -> [Turn] {
        guard let startDate = timeRange.startDate else { return store.allTurns }
        return store.allTurns.filter { $0.timestamp >= startDate }
    }
}
