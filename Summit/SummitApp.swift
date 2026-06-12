import SwiftUI
import SwiftData

@main
struct SummitApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AccountModel.self,
            TransactionModel.self,
            CategoryGroupModel.self,
            CategoryModel.self,
            GoalModel.self,
            ScheduledItemModel.self,
            BudgetMonthModel.self,
            BudgetAllocationModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var engine = BudgetEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .task {
                    await MainActor.run {
                        BudgetEngine.seedIfNeeded(context: sharedModelContainer.mainContext)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
