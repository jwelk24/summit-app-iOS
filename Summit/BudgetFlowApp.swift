import Combine
import SwiftUI

final class AppModel: ObservableObject {
    @Published var engine: BudgetEngine

    init(engine: BudgetEngine) {
        self.engine = engine
    }

    static var preview: AppModel {
        let engine = BudgetEngine.sample()
        return AppModel(engine: engine)
    }
}

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            BudgetView()
                .tabItem { Label("Budget", systemImage: "list.bullet.rectangle") }

            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "creditcard") }

            TimelineView()
                .tabItem { Label("Timeline", systemImage: "calendar") }
        }
    }
}

