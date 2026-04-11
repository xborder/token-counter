import Foundation
import SwiftUI

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
        return repository.turns(for: session)
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
