import SwiftUI

@main
struct TokenCounterApp: App {

    private let store = TokenStore()
    @State private var viewModel = MenuBarViewModel()
    @State private var logWatcher = ClaudeLogWatcher()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(viewModel: viewModel)
                .onAppear {
                    viewModel.configure(store: store)
                    logWatcher.onUpdate = { [self] in viewModel.refresh() }
                    logWatcher.start(store: store)
                }
        } label: {
            Image(systemName: "sum")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
