import WidgetKit
import SwiftUI

@main
struct SummitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SafeToSpendWidget()
        NetWorthWidget()
        BudgetRemainingWidget()
        UpcomingBillsWidget()
        SummitWidgetsControl()
        SpendingTodayLiveActivity()
    }
}
