import SwiftUI

@main
struct TokenCounterApp: App {

    // AppController is a reference type so it initializes once and starts
    // the log watcher eagerly at app launch — not waiting for the first popover open.
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(viewModel: controller.viewModel, controller: controller)
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Holds all app state. Initialized once at launch; starts the log watchers immediately.
@Observable
final class AppController {
    let store = TokenStore()
    let viewModel = MenuBarViewModel()
    private var claudeWatcher: ClaudeLogWatcher
    private var codexWatcher: CodexLogWatcher

    private var claudeLogBasePath: String
    private var codexLogBasePath: String
    private var refreshInterval: TimeInterval

    init() {
        let initialClaudeLogBasePath = AppSettings.claudeLogBasePath()
        let initialCodexLogBasePath = AppSettings.codexLogBasePath()
        let initialRefreshInterval = AppSettings.refreshInterval()

        claudeLogBasePath = initialClaudeLogBasePath
        codexLogBasePath = initialCodexLogBasePath
        refreshInterval = initialRefreshInterval
        claudeWatcher = ClaudeLogWatcher(basePath: initialClaudeLogBasePath, scanInterval: initialRefreshInterval)
        codexWatcher = CodexLogWatcher(basePath: initialCodexLogBasePath, scanInterval: initialRefreshInterval)

        viewModel.configure(store: store, refreshInterval: refreshInterval)
        configureWatchers()
        startWatchers()
    }

    func applySettings(
        claudeLogBasePath: String,
        codexLogBasePath: String,
        refreshInterval: TimeInterval,
        launchAtLogin: Bool
    ) throws {
        try LaunchAtLoginManager.setEnabled(launchAtLogin)

        let normalizedRefreshInterval = AppSettings.clampRefreshInterval(refreshInterval)
        let shouldRestartWatchers = self.claudeLogBasePath != claudeLogBasePath
            || self.codexLogBasePath != codexLogBasePath
            || self.refreshInterval != normalizedRefreshInterval

        self.claudeLogBasePath = claudeLogBasePath
        self.codexLogBasePath = codexLogBasePath
        self.refreshInterval = normalizedRefreshInterval

        viewModel.setRefreshInterval(normalizedRefreshInterval)

        if shouldRestartWatchers {
            stopWatchers()
            claudeWatcher = ClaudeLogWatcher(basePath: claudeLogBasePath, scanInterval: normalizedRefreshInterval)
            codexWatcher = CodexLogWatcher(basePath: codexLogBasePath, scanInterval: normalizedRefreshInterval)
            configureWatchers()
            startWatchers()
            viewModel.refresh()
        }
    }

    private func configureWatchers() {
        let refreshCallback: () -> Void = { [weak self] in
            self?.viewModel.refresh()
        }
        claudeWatcher.onUpdate = refreshCallback
        codexWatcher.onUpdate = refreshCallback
    }

    private func startWatchers() {
        claudeWatcher.start(store: store)
        codexWatcher.start(store: store)
    }

    private func stopWatchers() {
        claudeWatcher.stop()
        codexWatcher.stop()
    }
}

/// Menu bar label — shows "TC" text so it renders on any background and takes minimal space.
struct MenuBarIcon: View {
    var body: some View {
        Text("TC")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
    }
}
