import SwiftUI
import SwiftData

@main
struct TokenCounterApp: App {

    @State private var viewModel = MenuBarViewModel()
    @State private var logWatcher = ClaudeLogWatcher()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            Session.self,
            Turn.self,
            PricingTier.self,
        ])
        let config = ModelConfiguration(
            "TokenCounter",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(viewModel: viewModel)
                .modelContainer(sharedModelContainer)
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    viewModel.configure(modelContext: context)
                    logWatcher.start(modelContext: context)
                    assignCostsToExistingTurns(context: context)
                }
        } label: {
            Image(systemName: "sum")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }

    /// Assign costs to any turns that were ingested without cost calculation.
    private func assignCostsToExistingTurns(context: ModelContext) {
        let calculator = CostCalculator()
        let descriptor = FetchDescriptor<Turn>(
            predicate: #Predicate { $0.estimatedCostUSD == 0 }
        )
        if let turns = try? context.fetch(descriptor) {
            calculator.assignCosts(to: turns)
            try? context.save()
        }
    }
}
