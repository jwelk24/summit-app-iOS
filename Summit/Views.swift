import SwiftUI

private struct SelectedCategory: Identifiable, Equatable {
    let id: UUID
}

struct BudgetView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var assignAmount: String = ""
    @State private var selectedCategory: SelectedCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available to Budget: \(format(appModel.engine.availableToBudget(for: appModel.engine.selectedYear, month: appModel.engine.selectedMonth)))")
                    .font(.headline)
                    .accessibilityIdentifier("availableToBudgetLabel")
                Spacer()
                Button("Next Month") {
                    appModel.engine.rollToNextMonth(currentYear: appModel.engine.selectedYear, currentMonth: appModel.engine.selectedMonth)
                }
            }
            List {
                ForEach(appModel.engine.groups.sorted(by: { $0.sort < $1.sort })) { group in
                    Section(group.name) {
                        ForEach(appModel.engine.categories.filter { $0.groupId == group.id }.sorted(by: { $0.sort < $1.sort })) { cat in
                            let assigned = appModel.engine.monthRecord(year: appModel.engine.selectedYear, month: appModel.engine.selectedMonth)?.allocations[cat.id] ?? 0
                            let activity = appModel.engine.activity(for: cat.id, year: appModel.engine.selectedYear, month: appModel.engine.selectedMonth)
                            let available = appModel.engine.available(for: cat.id, year: appModel.engine.selectedYear, month: appModel.engine.selectedMonth)
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(cat.name)
                                    Text("Assigned: \(format(assigned))  Activity: \(format(activity))  Available: \(format(available))")
                                        .font(.caption)
                                        .foregroundStyle(available < 0 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                                }
                                Spacer()
                                Button("Assign") { selectedCategory = SelectedCategory(id: cat.id) }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .sheet(item: $selectedCategory) { selected in
            AssignSheet(categoryId: selected.id)
                .environmentObject(appModel)
        }
        .accessibilityIdentifier("budgetScreen")
        .navigationTitle("Budget")
    }

    private func format(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: n) ?? "$0"
    }
}

private struct AssignSheet: View, Identifiable {
    var id: UUID { categoryId }
    let categoryId: UUID
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                #if canImport(UIKit)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                #else
                TextField("Amount", text: $amountText)
                #endif
            }
            .navigationTitle("Assign Funds")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") {
                        let amt = Decimal(string: amountText) ?? 0
                        appModel.engine.assign(amt, to: categoryId, year: appModel.engine.selectedYear, month: appModel.engine.selectedMonth)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TransactionsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            ForEach(appModel.engine.transactions.sorted(by: { $0.date > $1.date }), id: \.id) { tx in
                HStack {
                    VStack(alignment: .leading) {
                        Text(tx.merchant)
                        Text(tx.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(format(tx.amount))
                        .foregroundStyle(tx.amount < 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.green))
                }
            }
        }
        .navigationTitle("Transactions")
    }

    private func format(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: n) ?? "$0"
    }
}

private struct TimelineEvent: Identifiable, Equatable {
    let id: String
    let name: String
    let date: Date
    let amount: Decimal
}

struct TimelineView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projected 30 Days (stub)").font(.headline)
            List {
                ForEach(Array(projectedEvents().prefix(20))) { (ev: TimelineEvent) in
                    HStack {
                        Text(ev.name)
                        Spacer()
                        Text(ev.date, style: .date)
                        Text(format(ev.amount))
                            .foregroundStyle(ev.amount < 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.green))
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Timeline")
    }

    private func projectedEvents() -> [TimelineEvent] {
        let today = Date()
        let in30 = Calendar.current.date(byAdding: .day, value: 30, to: today)!
        let events: [TimelineEvent] = appModel.engine.scheduled.compactMap { item in
            guard item.nextDate <= in30 else { return nil }
            let id = "\(item.name)|\(item.nextDate.timeIntervalSince1970)"
            return TimelineEvent(id: id, name: item.name, date: item.nextDate, amount: item.amount)
        }
        return events.sorted { $0.date < $1.date }
    }

    private func format(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: n) ?? "$0"
    }
}
