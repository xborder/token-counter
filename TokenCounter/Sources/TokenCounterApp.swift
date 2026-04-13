import SwiftUI

@main
struct TokenCounterApp: App {

    // AppController is a reference type so it initializes once and starts
    // the log watcher eagerly at app launch — not waiting for the first popover open.
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(viewModel: controller.viewModel)
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
    let claudeWatcher = ClaudeLogWatcher()
    let codexWatcher = CodexLogWatcher()

    init() {
        viewModel.configure(store: store)
        let refreshCallback: () -> Void = { [weak self] in
            self?.viewModel.refresh()
        }
        claudeWatcher.onUpdate = refreshCallback
        codexWatcher.onUpdate = refreshCallback
        claudeWatcher.start(store: store)
        codexWatcher.start(store: store)
    }
}

/// Menu bar label — shows "TC" text so it renders on any background and takes minimal space.
struct MenuBarIcon: View {
    var body: some View {
        Text("TC")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
    }
}
