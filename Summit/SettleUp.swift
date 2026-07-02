import SwiftUI
import SwiftData

// MARK: - Balance engine

enum SettleUp {
    /// Net balance for `me`: positive means the household owes you, negative
    /// means you owe. Exact for a two-person household (the couples case).
    static func netBalance(expenses: [SharedExpenseModel], settlements: [SettlementModel], me: UUID) -> Decimal {
        var balance: Decimal = 0
        for e in expenses {
            let owedToPayer = e.amount - e.payerShare
            if e.payerUserID == me { balance += owedToPayer }
            else { balance -= owedToPayer }
        }
        for s in settlements {
            if s.fromUserID == me { balance += s.amount }
            else if s.toUserID == me { balance -= s.amount }
        }
        return balance
    }
}

// MARK: - Settle Up view

struct SettleUpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \SharedExpenseModel.date, order: .reverse) private var allExpenses: [SharedExpenseModel]
    @Query(sort: \SettlementModel.date, order: .reverse) private var allSettlements: [SettlementModel]

    @State private var members: [HouseholdMembership] = []
    @State private var loaded = false
    @State private var showingAdd = false

    private var householdID: UUID? { HouseholdService.shared.currentHousehold?.id }
    private var me: UUID? { SupabaseService.shared.currentUserID }
    private var other: UUID? { members.map(\.user_id).first { $0 != me } }

    private var expenses: [SharedExpenseModel] { allExpenses.filter { $0.householdID == householdID } }
    private var settlements: [SettlementModel] { allSettlements.filter { $0.householdID == householdID } }

    private var balance: Decimal {
        guard let me else { return 0 }
        return SettleUp.netBalance(expenses: expenses, settlements: settlements, me: me)
    }

    var body: some View {
        NavigationStack {
            Group {
                if members.count < 2 {
                    ContentUnavailableView {
                        Label("Invite Your Partner", systemImage: "person.2")
                    } description: {
                        Text(loaded
                             ? "Settle Up tracks shared expenses between household members. Invite a partner from Sync & Account to get started."
                             : "Loading…")
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if members.count >= 2 {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAdd = true } label: { Image(systemName: "plus") }
                            .accessibilityIdentifier("addSharedExpenseButton")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                if let householdID, let me, let other {
                    AddSharedExpenseView(householdID: householdID, me: me, other: other)
                }
            }
            .task {
                if !loaded { members = await HouseholdService.shared.members(); loaded = true }
            }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 12) {
            SummitGlassCard {
                SummitHeroHeader(systemImage: "person.2.fill", label: "Between You & Your Partner")
                SummitHeroAmount(
                    caption: balanceCaption,
                    value: currency(balance < 0 ? -balance : balance),
                    tint: balance == 0 ? .secondary : (balance > 0 ? .green : .orange)
                )
                if balance != 0 {
                    Button {
                        settleUp()
                    } label: {
                        Label("Settle Up", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("You're all settled up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            List {
                if expenses.isEmpty && settlements.isEmpty {
                    Text("No shared expenses yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("Activity") {
                        ForEach(activity, id: \.id) { item in
                            ActivityRow(item: item, me: me)
                        }
                    }
                    .summitRowBackground()
                }
            }
            .summitListBackground()
        }
    }

    private var balanceCaption: String {
        if balance > 0 { return "Your partner owes you" }
        if balance < 0 { return "You owe your partner" }
        return "Settled up"
    }

    // Unified, date-sorted activity feed.
    private struct ActivityItem: Identifiable {
        let id: UUID
        let date: Date
        let title: String
        let amount: Decimal
        let isSettlement: Bool
        let payerIsMe: Bool
    }

    private var activity: [ActivityItem] {
        var items: [ActivityItem] = []
        for e in expenses {
            items.append(ActivityItem(id: e.id, date: e.date, title: e.title, amount: e.amount,
                                      isSettlement: false, payerIsMe: e.payerUserID == me))
        }
        for s in settlements {
            items.append(ActivityItem(id: s.id, date: s.date, title: "Settlement", amount: s.amount,
                                      isSettlement: true, payerIsMe: s.fromUserID == me))
        }
        return items.sorted { $0.date > $1.date }
    }

    private struct ActivityRow: View {
        let item: ActivityItem
        let me: UUID?
        var body: some View {
            HStack {
                Image(systemName: item.isSettlement ? "arrow.left.arrow.right.circle.fill" : "cart.fill")
                    .foregroundStyle(item.isSettlement ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                    Text("\(item.payerIsMe ? "You" : "Partner") · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(currency(item.amount)).monospacedDigit()
            }
        }
        private func currency(_ d: Decimal) -> String { SettleUpFormat.currency(d) }
    }

    private func settleUp() {
        guard let householdID, let me, let other, balance != 0 else { return }
        let amount = balance < 0 ? -balance : balance
        // If I owe (balance < 0), I pay my partner; otherwise record that they paid me.
        let settlement = SettlementModel(
            householdID: householdID,
            fromUserID: balance < 0 ? me : other,
            toUserID: balance < 0 ? other : me,
            amount: amount
        )
        context.insert(settlement)
        try? context.save()
    }

    private func currency(_ d: Decimal) -> String { SettleUpFormat.currency(d) }
}

// MARK: - Add shared expense

struct AddSharedExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let householdID: UUID
    let me: UUID
    let other: UUID

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var paidByMe = true
    @State private var splitEvenly = true
    @State private var payerShareText = ""
    @State private var note = ""

    private var amount: Decimal { Decimal(string: amountText.trimmingCharacters(in: .whitespaces)) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it for?", text: $title)
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("$0", text: $amountText)
                            .multilineTextAlignment(.trailing)
                            #if canImport(UIKit)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Split") {
                    Picker("Paid by", selection: $paidByMe) {
                        Text("You").tag(true)
                        Text("Partner").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Split evenly (50/50)", isOn: $splitEvenly)
                    if !splitEvenly {
                        HStack {
                            Text("Payer's share")
                            Spacer()
                            TextField("$0", text: $payerShareText)
                                .multilineTextAlignment(.trailing)
                                #if canImport(UIKit)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                    }
                }

                Section {
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Shared Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(amount <= 0 || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let payerShare = splitEvenly
            ? amount / 2
            : (Decimal(string: payerShareText.trimmingCharacters(in: .whitespaces)) ?? amount / 2)
        let expense = SharedExpenseModel(
            householdID: householdID,
            title: title.trimmingCharacters(in: .whitespaces),
            amount: amount,
            date: date,
            payerUserID: paidByMe ? me : other,
            payerShare: payerShare,
            note: note.isEmpty ? nil : note
        )
        context.insert(expense)
        try? context.save()
        dismiss()
    }
}

enum SettleUpFormat {
    static func currency(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "$0"
    }
}
