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

/// Holds all app state. Initialized once at launch; starts the log watcher immediately.
@Observable
final class AppController {
    let store = TokenStore()
    let viewModel = MenuBarViewModel()
    let logWatcher = ClaudeLogWatcher()

    init() {
        viewModel.configure(store: store)
        logWatcher.onUpdate = { [weak self] in
            self?.viewModel.refresh()
        }
        logWatcher.start(store: store)
    }
}

/// A distinctive, legible menu bar icon.
struct MenuBarIcon: View {
    var body: some View {
        Image(systemName: "t.circle.fill")
            .font(.system(size: 14, weight: .medium))
    }
}
