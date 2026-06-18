import SwiftUI

private func currencyFormatter(_ code: String) -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = code
    f.maximumFractionDigits = 0
    return f
}

struct ContentView: View {
    @State private var snapshot: SummitSnapshot?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let snap = snapshot {
                    NetWorthBlock(snap: snap)
                    Divider()
                    BudgetBlock(snap: snap)
                    if let nextBill = snap.upcomingBills.first {
                        Divider()
                        BillBlock(bill: nextBill, currency: snap.currencyCode)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.gen3")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                        Text("Open Summit on your iPhone to sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Summit")
        .onAppear { snapshot = SummitSnapshot.load() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                snapshot = SummitSnapshot.load()
            }
        }
    }
}

private struct NetWorthBlock: View {
    let snap: SummitSnapshot
    var body: some View {
        let formatter = currencyFormatter(snap.currencyCode)
        VStack(alignment: .leading, spacing: 2) {
            Text("Net Worth")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatter.string(from: NSNumber(value: snap.netWorth)) ?? "$0")
                .font(.title3.bold())
                .foregroundStyle(snap.netWorth >= 0 ? Color.green : Color.red)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BudgetBlock: View {
    let snap: SummitSnapshot
    var body: some View {
        let formatter = currencyFormatter(snap.currencyCode)
        let frac = snap.budgetUsedFraction
        let tint: Color = frac > 0.9 ? .red : (frac > 0.7 ? .orange : .green)
        VStack(alignment: .leading, spacing: 4) {
            Text("Budget Left")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .center) {
                Text(formatter.string(from: NSNumber(value: snap.budgetRemaining)) ?? "$0")
                    .font(.headline)
                    .foregroundStyle(snap.budgetRemaining >= 0 ? Color.primary : Color.red)
                    .minimumScaleFactor(0.6)
                Spacer()
                Gauge(value: frac) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(tint)
                    .scaleEffect(0.7)
            }
            Text(snap.monthLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BillBlock: View {
    let bill: SummitSnapshot.BillSummary
    let currency: String
    var body: some View {
        let formatter = currencyFormatter(currency)
        VStack(alignment: .leading, spacing: 2) {
            Text("Next Bill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Text(bill.name).font(.footnote).lineLimit(1)
                Spacer()
                Text(formatter.string(from: NSNumber(value: abs(bill.amount))) ?? "$0")
                    .font(.footnote.bold())
            }
            Text(bill.date, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack { ContentView() }
}
