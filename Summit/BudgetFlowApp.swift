import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            BudgetView()
                .tabItem { Label("Budget", systemImage: "list.bullet.rectangle") }

            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "creditcard") }

            NetWorthView()
                .tabItem { Label("Net Worth", systemImage: "chart.line.uptrend.xyaxis") }

            TimelineView()
                .tabItem { Label("Timeline", systemImage: "calendar") }
        }
    }
}
