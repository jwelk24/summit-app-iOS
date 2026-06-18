import WidgetKit
import SwiftUI

private func currencyFormatter(_ code: String) -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = code
    f.maximumFractionDigits = 0
    return f
}

struct SummitSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: SummitSnapshot
}

struct SummitSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummitSnapshotEntry {
        SummitSnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummitSnapshotEntry) -> Void) {
        let snap = SummitSnapshot.load() ?? .placeholder
        completion(SummitSnapshotEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummitSnapshotEntry>) -> Void) {
        let snap = SummitSnapshot.load() ?? .placeholder
        let entry = SummitSnapshotEntry(date: Date(), snapshot: snap)
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Net Worth

struct NetWorthWidgetView: View {
    let entry: SummitSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snap = entry.snapshot
        let nw = snap.netWorth
        let formatter = currencyFormatter(snap.currencyCode)
        VStack(alignment: .leading, spacing: 4) {
            Label("Net Worth", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatter.string(from: NSNumber(value: nw)) ?? "$0")
                .font(family == .systemSmall ? .title2 : .largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(nw >= 0 ? Color.green : Color.red)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            if family != .systemSmall {
                HStack {
                    Label {
                        Text(formatter.string(from: NSNumber(value: snap.totalAssets)) ?? "$0")
                    } icon: {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.green)
                    }
                    Spacer()
                    Label {
                        Text(formatter.string(from: NSNumber(value: snap.totalLiabilities)) ?? "$0")
                    } icon: {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.red)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct NetWorthWidget: Widget {
    let kind: String = "SummitNetWorthWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummitSnapshotProvider()) { entry in
            NetWorthWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Net Worth")
        .description("Your current net worth at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Budget Remaining

struct BudgetRemainingWidgetView: View {
    let entry: SummitSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snap = entry.snapshot
        let remaining = snap.budgetRemaining
        let frac = snap.budgetUsedFraction
        let formatter = currencyFormatter(snap.currencyCode)
        let tint: Color = frac > 0.9 ? .red : (frac > 0.7 ? .orange : .green)
        VStack(alignment: .leading, spacing: 4) {
            Label("Budget Left", systemImage: "wallet.pass.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatter.string(from: NSNumber(value: remaining)) ?? "$0")
                .font(family == .systemSmall ? .title2 : .largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(remaining >= 0 ? Color.primary : Color.red)
                .minimumScaleFactor(0.6)
            Text(snap.monthLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ProgressView(value: frac).tint(tint)
            HStack {
                Text(formatter.string(from: NSNumber(value: snap.budgetSpent)) ?? "$0")
                Spacer()
                Text("of \(formatter.string(from: NSNumber(value: snap.budgetAssigned)) ?? "$0")")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

struct BudgetRemainingWidget: Widget {
    let kind: String = "SummitBudgetRemainingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummitSnapshotProvider()) { entry in
            BudgetRemainingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Budget Remaining")
        .description("How much you have left to spend this month.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Upcoming Bills

struct UpcomingBillsWidgetView: View {
    let entry: SummitSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snap = entry.snapshot
        let formatter = currencyFormatter(snap.currencyCode)
        let maxRows: Int = (family == .systemLarge) ? 6 : 3
        VStack(alignment: .leading, spacing: 6) {
            Label("Upcoming Bills", systemImage: "calendar.badge.clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            if snap.upcomingBills.isEmpty {
                Spacer()
                Text("No bills due in the next 30 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(snap.upcomingBills.prefix(maxRows))) { bill in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bill.name).font(.subheadline).lineLimit(1)
                            Text(bill.date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatter.string(from: NSNumber(value: abs(bill.amount))) ?? "$0")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
    }
}

struct UpcomingBillsWidget: Widget {
    let kind: String = "SummitUpcomingBillsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummitSnapshotProvider()) { entry in
            UpcomingBillsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Upcoming Bills")
        .description("Bills coming due in the next 30 days.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    NetWorthWidget()
} timeline: {
    SummitSnapshotEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    BudgetRemainingWidget()
} timeline: {
    SummitSnapshotEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    UpcomingBillsWidget()
} timeline: {
    SummitSnapshotEntry(date: .now, snapshot: .placeholder)
}
