import ActivityKit
import WidgetKit
import SwiftUI

private func liveActivityCurrencyFormatter(_ code: String) -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = code
    f.maximumFractionDigits = 0
    return f
}

private func progressTint(_ frac: Double) -> Color {
    if frac > 1.0 { return .red }
    if frac > 0.85 { return .orange }
    return .green
}

struct SpendingTodayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpendingTodayAttributes.self) { context in
            SpendingTodayLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let frac = context.attributes.dailyBudget > 0
                ? context.state.spentToday / context.attributes.dailyBudget
                : 0
            let formatter = liveActivityCurrencyFormatter(context.attributes.currencyCode)
            let spentStr = formatter.string(from: NSNumber(value: context.state.spentToday)) ?? "$0"
            let budgetStr = formatter.string(from: NSNumber(value: context.attributes.dailyBudget)) ?? "$0"

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Spent", systemImage: "creditcard.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.transactionCount) tx")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(spentStr)
                        .font(.title2.bold())
                        .foregroundStyle(progressTint(frac))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: min(frac, 1.0)).tint(progressTint(frac))
                        HStack {
                            Text("Daily budget \(budgetStr)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let merchant = context.state.topMerchant {
                                Text(merchant)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(progressTint(frac))
            } compactTrailing: {
                Text(spentStr)
                    .font(.caption.bold())
                    .foregroundStyle(progressTint(frac))
            } minimal: {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(progressTint(frac))
            }
        }
    }
}

private struct SpendingTodayLockScreenView: View {
    let context: ActivityViewContext<SpendingTodayAttributes>

    var body: some View {
        let formatter = liveActivityCurrencyFormatter(context.attributes.currencyCode)
        let frac = context.attributes.dailyBudget > 0
            ? context.state.spentToday / context.attributes.dailyBudget
            : 0
        let spentStr = formatter.string(from: NSNumber(value: context.state.spentToday)) ?? "$0"
        let budgetStr = formatter.string(from: NSNumber(value: context.attributes.dailyBudget)) ?? "$0"

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(spentStr)
                        .font(.title.bold())
                        .foregroundStyle(progressTint(frac))
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Daily Budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(budgetStr)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(frac, 1.0)).tint(progressTint(frac))
            HStack {
                Text("\(context.state.transactionCount) transactions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let merchant = context.state.topMerchant {
                    Text("Last: \(merchant)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

extension SpendingTodayAttributes {
    fileprivate static var preview: SpendingTodayAttributes {
        SpendingTodayAttributes(
            monthLabel: "June 2026",
            currencyCode: "USD",
            dailyBudget: 120,
            startedAt: Date()
        )
    }
}

extension SpendingTodayAttributes.ContentState {
    fileprivate static var sample: SpendingTodayAttributes.ContentState {
        SpendingTodayAttributes.ContentState(
            spentToday: 78,
            transactionCount: 3,
            topMerchant: "Chipotle",
            asOf: Date()
        )
    }
}

#Preview("Lock Screen", as: .content, using: SpendingTodayAttributes.preview) {
    SpendingTodayLiveActivity()
} contentStates: {
    SpendingTodayAttributes.ContentState.sample
}
