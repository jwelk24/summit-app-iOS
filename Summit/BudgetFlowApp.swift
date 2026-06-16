import SwiftUI

struct RootView: View {
    @AppStorage("budgetTitle") private var budgetTitle: String = "Budget"

    var body: some View {
        TabView {
            BudgetView()
                .tabItem { Label(budgetTitle, systemImage: "list.bullet.rectangle") }

            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "creditcard") }

            NetWorthView()
                .tabItem { Label("Net Worth", systemImage: "chart.line.uptrend.xyaxis") }

            HorizonView()
                .tabItem { Label("Horizon", systemImage: "mountain.2") }

            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.pie") }
        }
    }
}
