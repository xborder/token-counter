import Foundation
import SwiftUI

/// UI variants for the menu bar popover.
enum UIVariant: Int, CaseIterable, Identifiable {
    case classic = 0           // Current layout: header → breakdown → models → sessions
    case compact = 1           // Dense cards, minimal spacing
    case minimal = 2           // Only cost and tokens, hide breakdown details
    case tabbed = 3            // Tabs: Summary | Breakdown | Models | Sessions
    case cardGrid = 4          // Dashboard with large metric cards
    case treeOnly = 5          // Full session tree, no breakdown
    case costFocused = 6       // Emphasize cost breakdown, de-emphasize tokens
    case timelineView = 7      // Sessions as chronological timeline
    case comparison = 8        // Side-by-side comparison of providers
    case sparklines = 9        // Sparkline charts for trends

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .classic: return "Classic"
        case .compact: return "Compact"
        case .minimal: return "Minimal"
        case .tabbed: return "Tabbed"
        case .cardGrid: return "Card Grid"
        case .treeOnly: return "Tree Only"
        case .costFocused: return "Cost Focused"
        case .timelineView: return "Timeline"
        case .comparison: return "Comparison"
        case .sparklines: return "Sparklines"
        }
    }

    var description: String {
        switch self {
        case .classic:
            return "Current layout: Header → Breakdown → Models → Sessions"
        case .compact:
            return "Dense cards with minimal spacing for more data"
        case .minimal:
            return "Only total cost and tokens, hide details"
        case .tabbed:
            return "Tabbed interface: Summary | Breakdown | Models | Sessions"
        case .cardGrid:
            return "Dashboard with large metric cards"
        case .treeOnly:
            return "Full session tree without breakdown analysis"
        case .costFocused:
            return "Emphasize cost breakdown over token details"
        case .timelineView:
            return "Sessions displayed as chronological timeline"
        case .comparison:
            return "Side-by-side comparison of Claude vs OpenAI"
        case .sparklines:
            return "Mini charts showing token/cost trends"
        }
    }
}

/// ViewModel for the menu bar popover. Drives all UI state.
@Observable
final class MenuBarViewModel {

    // MARK: - State

    var selectedTimeRange: TokenUsageRepository.TimeRange = .today
    var selectedProvider: TokenUsageRepository.ProviderFilter = .all
    var summary: TokenUsageRepository.UsageSummary = .init()
    var modelBreakdown: [TokenUsageRepository.ModelUsage] = []
    var projects: [Project] = []
    var expandedModels: Set<String> = []
    var expandedProjects: Set<String> = []
    var expandedSessions: Set<String> = []
    var lastUpdated: Date = Date()
    var showSettings = false
    var selectedUIVariant: UIVariant = .classic
    var showVariantSelector = false

    // MARK: - Dependencies

    private var repository: TokenUsageRepository?
    private var costCalculator = CostCalculator()
    private var refreshTimer: Timer?

    // MARK: - Setup

    func configure(store: TokenStore) {
        self.repository = TokenUsageRepository(store: store)
        refresh()
        startAutoRefresh()
    }

    // MARK: - Actions

    func refresh() {
        guard let repository else { return }

        summary = repository.summary(for: selectedTimeRange, provider: selectedProvider)
        modelBreakdown = repository.modelBreakdown(for: selectedTimeRange, provider: selectedProvider)
        projects = repository.projects(for: selectedTimeRange)
        lastUpdated = Date()
    }

    func selectTimeRange(_ range: TokenUsageRepository.TimeRange) {
        selectedTimeRange = range
        refresh()
    }

    func selectProvider(_ provider: TokenUsageRepository.ProviderFilter) {
        selectedProvider = provider
        refresh()
    }

    func toggleModel(_ model: String) {
        if expandedModels.contains(model) {
            expandedModels.remove(model)
        } else {
            expandedModels.insert(model)
        }
    }

    func toggleProject(_ projectPath: String) {
        if expandedProjects.contains(projectPath) {
            expandedProjects.remove(projectPath)
        } else {
            expandedProjects.insert(projectPath)
        }
    }

    func toggleSession(_ sessionId: String) {
        if expandedSessions.contains(sessionId) {
            expandedSessions.remove(sessionId)
        } else {
            expandedSessions.insert(sessionId)
        }
    }

    func sessions(for project: Project) -> [Session] {
        guard let repository else { return [] }
        return repository.sessions(for: project, timeRange: selectedTimeRange)
    }

    func turns(for session: Session) -> [Turn] {
        guard let repository else { return [] }
        return repository.turns(for: session, timeRange: selectedTimeRange)
    }

    // MARK: - Auto-refresh

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
