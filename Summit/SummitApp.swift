import SwiftUI
import SwiftData

enum SummitSharedStore {
    static let appGroupID = "group.com.welker.Summit"
    static let storeFilename = "Summit.sqlite"

    static var schema: Schema {
        Schema([
            AccountModel.self,
            TransactionModel.self,
            TransactionSplitModel.self,
            CategoryGroupModel.self,
            CategoryModel.self,
            GoalModel.self,
            ScheduledItemModel.self,
            BudgetMonthModel.self,
            BudgetAllocationModel.self,
            BalanceSnapshotModel.self,
            PlaidAccountLinkModel.self,
            PlaidTransactionLinkModel.self,
            InvestmentHoldingModel.self,
            InvestmentTransactionModel.self,
            LiabilityModel.self,
        ])
    }

    static func makeConfiguration() -> ModelConfiguration {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let storeURL = groupURL.appendingPathComponent(storeFilename)
            return ModelConfiguration(schema: schema, url: storeURL)
        }
        return ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    }
}

@main
struct SummitApp: App {
    let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: SummitSharedStore.schema, configurations: [SummitSharedStore.makeConfiguration()])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var engine = BudgetEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .task {
                    await MainActor.run {
                        BudgetEngine.seedIfNeeded(context: sharedModelContainer.mainContext)
                        SummitSnapshotWriter.write(context: sharedModelContainer.mainContext)
                        SpendingTodayActivityManager.startOrUpdate(context: sharedModelContainer.mainContext)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                Task { @MainActor in
                    SummitSnapshotWriter.write(context: sharedModelContainer.mainContext)
                    SpendingTodayActivityManager.startOrUpdate(context: sharedModelContainer.mainContext)
                }
            case .active:
                Task { @MainActor in
                    SpendingTodayActivityManager.startOrUpdate(context: sharedModelContainer.mainContext)
                }
            default:
                break
            }
        }
    }
}
