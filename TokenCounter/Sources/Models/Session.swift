import Foundation
import SwiftData

@Model
final class Session {
    /// Session UUID from the JSONL logs.
    @Attribute(.unique) var sessionId: String

    var project: Project?

    var startedAt: Date
    var lastActivityAt: Date

    /// Git branch active during this session.
    var gitBranch: String?

    /// Human-readable session slug, e.g. "woolly-inventing-pine".
    var slug: String?

    /// Working directory path.
    var cwd: String?

    @Relationship(deleteRule: .cascade, inverse: \Turn.session)
    var turns: [Turn] = []

    init(
        sessionId: String,
        startedAt: Date,
        lastActivityAt: Date,
        gitBranch: String? = nil,
        slug: String? = nil,
        cwd: String? = nil
    ) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.gitBranch = gitBranch
        self.slug = slug
        self.cwd = cwd
    }

    // MARK: - Computed aggregations

    var totalInputTokens: Int {
        turns.reduce(0) { $0 + $1.inputTokens }
    }

    var totalOutputTokens: Int {
        turns.reduce(0) { $0 + $1.outputTokens }
    }

    var totalCacheCreationTokens: Int {
        turns.reduce(0) { $0 + $1.cacheCreationTokens }
    }

    var totalCacheReadTokens: Int {
        turns.reduce(0) { $0 + $1.cacheReadTokens }
    }

    var totalTokens: Int {
        turns.reduce(0) { $0 + $1.totalTokens }
    }

    var totalEstimatedCost: Double {
        turns.reduce(0) { $0 + $1.estimatedCostUSD }
    }
}
