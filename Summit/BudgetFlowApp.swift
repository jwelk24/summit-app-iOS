import SwiftUI

struct RootView: View {
    @AppStorage("budgetTitle") private var budgetTitle: String = "Budget"
    @AppStorage("budgetIcon") private var budgetIcon: String = "list.bullet.rectangle"
    @AppStorage("transactionsTitle") private var transactionsTitle: String = "Transactions"
    @AppStorage("transactionsIcon") private var transactionsIcon: String = "creditcard"
    @AppStorage("netWorthTitle") private var netWorthTitle: String = "Net Worth"
    @AppStorage("netWorthIcon") private var netWorthIcon: String = "chart.line.uptrend.xyaxis"
    @AppStorage("horizonTitle") private var horizonTitle: String = "Horizon"
    @AppStorage("horizonIcon") private var horizonIcon: String = "mountain.2"
    @AppStorage("reportsTitle") private var reportsTitle: String = "Reports"
    @AppStorage("reportsIcon") private var reportsIcon: String = "chart.pie"
    @AppStorage("insightsTitle") private var insightsTitle: String = "Insights"
    @AppStorage("insightsIcon") private var insightsIcon: String = "sparkles"

    var body: some View {
        TabView {
            BudgetView()
                .tabItem { Label(budgetTitle, systemImage: budgetIcon) }

            TransactionsView()
                .tabItem { Label(transactionsTitle, systemImage: transactionsIcon) }

            NetWorthView()
                .tabItem { Label(netWorthTitle, systemImage: netWorthIcon) }

            HorizonView()
                .tabItem { Label(horizonTitle, systemImage: horizonIcon) }

            ReportsView()
                .tabItem { Label(reportsTitle, systemImage: reportsIcon) }

            AIInsightsView()
                .tabItem { Label(insightsTitle, systemImage: insightsIcon) }
        }
    }
}
