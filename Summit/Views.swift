import SwiftUI
import SwiftData

// MARK: - BudgetView

struct BudgetView: View {
    @Environment(BudgetEngine.self) private var engine
    @Environment(\.modelContext) private var context

    @Query private var groups: [CategoryGroupModel]
    @Query private var categories: [CategoryModel]
    @Query private var transactions: [TransactionModel]
    @Query private var months: [BudgetMonthModel]

    @State private var assignTarget: CategoryModel?
    @State private var showingMove = false
    @State private var showingManageCategories = false

    private var budgetMonth: BudgetMonthModel? {
        months.first { $0.year == engine.selectedYear && $0.month == engine.selectedMonth }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Available to Budget: \(currency(BudgetEngine.availableToBudget(transactions: transactions, budgetMonth: budgetMonth, year: engine.selectedYear, month: engine.selectedMonth)))")
                    .font(.headline)
                    .accessibilityIdentifier("availableToBudgetLabel")
                    .padding(.horizontal)

                List {
                    ForEach(groups.sorted(by: { $0.sort < $1.sort })) { group in
                        Section(group.name) {
                            ForEach(categories.filter { $0.group?.id == group.id }.sorted(by: { $0.sort < $1.sort })) { cat in
                                CategoryRow(
                                    category: cat,
                                    budgetMonth: budgetMonth,
                                    year: engine.selectedYear,
                                    month: engine.selectedMonth,
                                    onAssign: { assignTarget = cat }
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingMove = true
                        } label: {
                            Label("Move Money", systemImage: "arrow.left.arrow.right")
                        }
                        .disabled(budgetMonth == nil || categories.count < 2)

                        Button {
                            let bm = engine.ensureMonth(year: engine.selectedYear, month: engine.selectedMonth, context: context)
                            engine.rollToNextMonth(from: bm, transactions: transactions, categories: categories, context: context)
                        } label: {
                            Label("Roll to Next Month", systemImage: "arrow.right.circle")
                        }

                        Divider()

                        Button {
                            showingManageCategories = true
                        } label: {
                            Label("Manage Categories", systemImage: "folder.badge.gearshape")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("budgetActionsMenu")
                }
            }
            .sheet(item: $assignTarget) { cat in
                AssignSheet(category: cat)
            }
            .sheet(isPresented: $showingMove) {
                if let bm = budgetMonth {
                    MoveMoneySheet(budgetMonth: bm)
                }
            }
            .sheet(isPresented: $showingManageCategories) {
                NavigationStack {
                    CategoriesManagementView()
                }
            }
            .accessibilityIdentifier("budgetScreen")
        }
    }
}

private struct MoveMoneySheet: View {
    let budgetMonth: BudgetMonthModel

    @Environment(BudgetEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var categories: [CategoryModel]

    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var amountText: String = ""

    private var sortedCategories: [CategoryModel] {
        categories.sorted(by: { $0.name < $1.name })
    }

    private var sourceAvailable: Decimal {
        guard let from = categories.first(where: { $0.id == fromID }) else { return 0 }
        return BudgetEngine.available(for: from, in: budgetMonth, year: budgetMonth.year, month: budgetMonth.month)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("From", selection: $fromID) {
                    Text("Select…").tag(UUID?.none)
                    ForEach(sortedCategories) { cat in
                        let assigned = BudgetEngine.assigned(for: cat, in: budgetMonth)
                        Text("\(cat.name) (\(currency(assigned)))").tag(Optional(cat.id))
                    }
                }

                Picker("To", selection: $toID) {
                    Text("Select…").tag(UUID?.none)
                    ForEach(sortedCategories) { cat in
                        Text(cat.name).tag(Optional(cat.id))
                    }
                }

                #if canImport(UIKit)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                #else
                TextField("Amount", text: $amountText)
                #endif

                if fromID != nil {
                    HStack {
                        Text("Source available").foregroundStyle(.secondary)
                        Spacer()
                        Text(currency(sourceAvailable))
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Move Money")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        guard let from = fromID, let to = toID, from != to else { return false }
        let amount = Decimal(string: amountText) ?? 0
        return amount > 0
    }

    private func save() {
        guard let from = categories.first(where: { $0.id == fromID }),
              let to = categories.first(where: { $0.id == toID }),
              let amount = Decimal(string: amountText), amount > 0 else { return }
        engine.coverOverspending(from: from, to: to, amount: amount, in: budgetMonth, context: context)
        dismiss()
    }
}

private struct CategoryRow: View {
    let category: CategoryModel
    let budgetMonth: BudgetMonthModel?
    let year: Int
    let month: Int
    let onAssign: () -> Void

    var body: some View {
        let assigned = BudgetEngine.assigned(for: category, in: budgetMonth)
        let activity = BudgetEngine.activity(for: category, year: year, month: month)
        let available = BudgetEngine.available(for: category, in: budgetMonth, year: year, month: month)
        HStack {
            VStack(alignment: .leading) {
                Text(category.name)
                Text("Assigned: \(currency(assigned))  Activity: \(currency(activity))  Available: \(currency(available))")
                    .font(.caption)
                    .foregroundStyle(available < 0 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            }
            Spacer()
            Button("Assign", action: onAssign)
        }
    }
}

private struct AssignSheet: View {
    let category: CategoryModel
    @Environment(BudgetEngine.self) private var engine
    @Environment(\.modelContext) private var context
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
            .navigationTitle("Assign to \(category.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") {
                        let amount = Decimal(string: amountText) ?? 0
                        let bm = engine.ensureMonth(year: engine.selectedYear, month: engine.selectedMonth, context: context)
                        engine.assign(amount, to: category, in: bm, context: context)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - TransactionsView

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TransactionModel.date, order: .reverse) private var transactions: [TransactionModel]

    @State private var showingNew = false
    @State private var editing: TransactionModel?

    var body: some View {
        NavigationStack {
            List {
                ForEach(transactions) { tx in
                    Button { editing = tx } label: {
                        TransactionRow(transaction: tx)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: {
                        Label("Add Transaction", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addTransactionButton")
                }
            }
            .sheet(isPresented: $showingNew) {
                TransactionEditor(editing: nil)
            }
            .sheet(item: $editing) { tx in
                TransactionEditor(editing: tx)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(transactions[index])
        }
        try? context.save()
    }
}

private struct TransactionRow: View {
    let transaction: TransactionModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                HStack(spacing: 6) {
                    Text(transaction.date, style: .date)
                    if let category = transaction.category {
                        Text("·")
                        Text(category.name)
                    } else {
                        Text("·")
                        Text("Uncategorized")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(currency(transaction.amount))
                .foregroundStyle(transaction.amount < 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.green))
        }
        .contentShape(Rectangle())
    }
}

private struct TransactionEditor: View {
    let editing: TransactionModel?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [AccountModel]
    @Query private var categories: [CategoryModel]

    @State private var isInflow: Bool = false
    @State private var amountText: String = ""
    @State private var merchant: String = ""
    @State private var memo: String = ""
    @State private var date: Date = Date()
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var cleared: Bool = false
    @State private var didLoad: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $isInflow) {
                    Text("Outflow").tag(false)
                    Text("Inflow").tag(true)
                }
                .pickerStyle(.segmented)

                #if canImport(UIKit)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                #else
                TextField("Amount", text: $amountText)
                #endif

                TextField("Merchant", text: $merchant)

                DatePicker("Date", selection: $date, displayedComponents: .date)

                Picker("Account", selection: $accountID) {
                    Text("Select…").tag(UUID?.none)
                    ForEach(accounts.sorted(by: { $0.name < $1.name })) { acc in
                        Text(acc.name).tag(Optional(acc.id))
                    }
                }

                Picker("Category", selection: $categoryID) {
                    Text("Uncategorized").tag(UUID?.none)
                    ForEach(categories.sorted(by: { $0.name < $1.name })) { cat in
                        Text(cat.name).tag(Optional(cat.id))
                    }
                }

                TextField("Memo (optional)", text: $memo)

                Toggle("Cleared", isOn: $cleared)
            }
            .navigationTitle(editing == nil ? "New Transaction" : "Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private var canSave: Bool {
        guard accountID != nil, !merchant.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let magnitude = Decimal(string: amountText) ?? 0
        return magnitude > 0
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let tx = editing else { return }
        isInflow = tx.amount >= 0
        amountText = formatPlain(abs(tx.amount))
        merchant = tx.merchant
        memo = tx.memo ?? ""
        date = tx.date
        accountID = tx.account?.id
        categoryID = tx.category?.id
        cleared = tx.cleared
    }

    private func save() {
        let magnitude = Decimal(string: amountText) ?? 0
        let signed = isInflow ? magnitude : -magnitude
        let account = accounts.first { $0.id == accountID }
        let category = categories.first { $0.id == categoryID }
        let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)

        if let tx = editing {
            tx.amount = signed
            tx.merchant = merchant
            tx.memo = trimmedMemo.isEmpty ? nil : trimmedMemo
            tx.date = date
            tx.account = account
            tx.category = category
            tx.cleared = cleared
        } else {
            let tx = TransactionModel(
                date: date,
                amount: signed,
                merchant: merchant,
                memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                cleared: cleared,
                account: account,
                category: category
            )
            context.insert(tx)
        }
        try? context.save()
        dismiss()
    }

}

// MARK: - NetWorthView

struct NetWorthView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [AccountModel]

    @State private var showingNew = false
    @State private var editing: AccountModel?

    private var assets: [AccountModel] {
        accounts.filter { $0.type.isAsset }.sorted { $0.name < $1.name }
    }
    private var liabilities: [AccountModel] {
        accounts.filter { !$0.type.isAsset }.sorted { $0.name < $1.name }
    }
    private var totalAssets: Decimal { assets.reduce(.zero) { $0 + $1.balance } }
    private var totalLiabilities: Decimal { liabilities.reduce(.zero) { $0 + abs($1.balance) } }
    private var netWorth: Decimal { totalAssets - totalLiabilities }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Net Worth").font(.headline)
                        Spacer()
                        Text(currency(netWorth))
                            .font(.title2).bold()
                            .foregroundStyle(netWorth >= 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.red))
                    }
                    HStack {
                        Text("Total Assets").foregroundStyle(.secondary)
                        Spacer()
                        Text(currency(totalAssets))
                    }
                    HStack {
                        Text("Total Liabilities").foregroundStyle(.secondary)
                        Spacer()
                        Text("-\(currency(totalLiabilities))")
                    }
                }

                if !assets.isEmpty {
                    Section("Assets") {
                        ForEach(assets) { acc in
                            Button { editing = acc } label: { accountRow(acc) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !liabilities.isEmpty {
                    Section("Liabilities") {
                        ForEach(liabilities) { acc in
                            Button { editing = acc } label: { accountRow(acc) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if accounts.isEmpty {
                    Section {
                        Text("Add your first account using the + button.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Net Worth")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addAccountButton")
                }
            }
            .sheet(isPresented: $showingNew) { AccountEditor(editing: nil) }
            .sheet(item: $editing) { acc in AccountEditor(editing: acc) }
        }
    }

    private func accountRow(_ acc: AccountModel) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(acc.name)
                Text(acc.type.displayName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(currency(acc.balance))
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - TimelineView

private struct ProjectionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let kind: ScheduledKind
    let delta: Decimal
    let runningBalance: Decimal
    let item: ScheduledItemModel
}

struct TimelineView: View {
    @Environment(BudgetEngine.self) private var engine
    @Environment(\.modelContext) private var context

    @Query private var accounts: [AccountModel]
    @Query private var scheduled: [ScheduledItemModel]

    @State private var showingNewScheduled = false
    @State private var editingScheduled: ScheduledItemModel?

    var body: some View {
        NavigationStack {
            let points = projection()
            let starting = startingBalance()
            let lowest = points.map(\.runningBalance).min() ?? starting
            let due = pendingItems()

            List {
                Section {
                    HStack {
                        Text("Starting Balance").foregroundStyle(.secondary)
                        Spacer()
                        Text(currency(starting))
                    }
                    HStack {
                        Text("Lowest Projected").foregroundStyle(.secondary)
                        Spacer()
                        Text(currency(lowest))
                            .foregroundStyle(lowest < 0 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                    }
                    if let last = points.last {
                        HStack {
                            Text("90-Day Projected").foregroundStyle(.secondary)
                            Spacer()
                            Text(currency(last.runningBalance))
                                .bold()
                        }
                    }
                }

                if !due.isEmpty {
                    Section("Pending (Past Due)") {
                        ForEach(due) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text(item.nextDate, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(currency(item.amount))
                                        .foregroundStyle(item.amount < 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.green))
                                    Button("Post") {
                                        engine.postScheduled(item, context: context)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingScheduled = item
                            }
                        }
                    }
                }

                Section("Next 90 Days") {
                    if points.isEmpty {
                        Text("No scheduled income or bills in the next 90 days. Tap + to add one.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(points) { point in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(point.label)
                                    Text(point.date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(currency(point.delta))
                                        .foregroundStyle(point.delta < 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.green))
                                    Text("Bal \(currency(point.runningBalance))")
                                        .font(.caption)
                                        .foregroundStyle(point.runningBalance < 0 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingScheduled = point.item
                            }
                        }
                    }
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !due.isEmpty {
                        Button("Post All Due") {
                            engine.postAllDue(scheduled, context: context)
                        }
                        .accessibilityIdentifier("postAllDueButton")
                    }
                    Button { showingNewScheduled = true } label: {
                        Label("Add Scheduled", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addScheduledButton")
                }
            }
            .sheet(isPresented: $showingNewScheduled) { ScheduledEditor(editing: nil) }
            .sheet(item: $editingScheduled) { item in ScheduledEditor(editing: item) }
        }
    }

    private func pendingItems() -> [ScheduledItemModel] {
        let today = Calendar.current.startOfDay(for: Date())
        return scheduled.filter { $0.nextDate < today }.sorted { $0.nextDate < $1.nextDate }
    }

    private func startingBalance() -> Decimal {
        accounts
            .filter { $0.type == .checking || $0.type == .savings }
            .reduce(Decimal.zero) { $0 + $1.balance }
    }

    private func projection() -> [ProjectionPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let horizon = cal.date(byAdding: .day, value: 90, to: today) else { return [] }

        struct Event { let date: Date; let item: ScheduledItemModel }
        var events: [Event] = []

        for item in scheduled {
            var date = item.nextDate
            var safety = 0
            while date <= horizon, safety < 365 {
                if date >= today {
                    events.append(Event(date: date, item: item))
                }
                guard item.intervalDays > 0,
                      let next = cal.date(byAdding: .day, value: item.intervalDays, to: date) else { break }
                date = next
                safety += 1
            }
        }
        events.sort { $0.date < $1.date }

        var running = startingBalance()
        return events.map { event in
            running += event.item.amount
            return ProjectionPoint(date: event.date, label: event.item.name, kind: event.item.kind, delta: event.item.amount, runningBalance: running, item: event.item)
        }
    }
}

// MARK: - Categories Management

struct CategoriesManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CategoryGroupModel.sort) private var groups: [CategoryGroupModel]
    @Query(sort: \CategoryModel.sort) private var categories: [CategoryModel]

    @State private var editingGroup: CategoryGroupModel?
    @State private var editingCategory: CategoryModel?
    @State private var showingNewGroup = false
    @State private var newCategoryForGroup: CategoryGroupModel?
    @State private var showResetAlert = false

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    let groupCategories = categories
                        .filter { $0.group?.id == group.id }
                        .sorted(by: { $0.sort < $1.sort })
                    ForEach(groupCategories) { cat in
                        Button { editingCategory = cat } label: {
                            HStack {
                                Text(cat.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { from, to in
                        reorderCategories(in: group, from: from, to: to)
                    }
                    Button {
                        newCategoryForGroup = group
                    } label: {
                        Label("Add Category", systemImage: "plus.circle")
                            .foregroundStyle(.tint)
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Button { editingGroup = group } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }
            }

            Section("Danger Zone") {
                Button("Reset All Data", role: .destructive) {
                    showResetAlert = true
                }
                .accessibilityIdentifier("resetAllDataButton")
            }
        }
        .navigationTitle("Manage Categories")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(iOS)
                EditButton()
                #endif
                Button { showingNewGroup = true } label: {
                    Label("Add Group", systemImage: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingNewGroup) { GroupEditor(editing: nil) }
        .sheet(item: $editingGroup) { g in GroupEditor(editing: g) }
        .sheet(item: $editingCategory) { c in CategoryEditor(editing: c, defaultGroup: nil) }
        .sheet(item: $newCategoryForGroup) { g in CategoryEditor(editing: nil, defaultGroup: g) }
        .alert("Reset All Data?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                BudgetEngine.resetAllData(context: context)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes every account, transaction, category, group, scheduled item, goal, and budget month, then re-seeds the sample data. This cannot be undone.")
        }
    }

    private func reorderCategories(in group: CategoryGroupModel, from: IndexSet, to: Int) {
        var sorted = categories
            .filter { $0.group?.id == group.id }
            .sorted(by: { $0.sort < $1.sort })
        sorted.move(fromOffsets: from, toOffset: to)
        for (index, cat) in sorted.enumerated() {
            cat.sort = index
        }
        try? context.save()
    }
}

private struct GroupEditor: View {
    let editing: CategoryGroupModel?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CategoryGroupModel.sort) private var groups: [CategoryGroupModel]

    @State private var name: String = ""
    @State private var sort: Int = 0
    @State private var didLoad = false
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Stepper("Order: \(sort)", value: $sort, in: 0...99)
                }
                if editing != nil {
                    Section {
                        Button("Delete Group", role: .destructive) { showDeleteAlert = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Group" : "Edit Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .alert("Delete Group?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let g = editing {
                        context.delete(g)
                        try? context.save()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                let count = editing?.categories.count ?? 0
                Text(count == 0
                     ? "This group has no categories."
                     : "This will also delete \(count) categor\(count == 1 ? "y" : "ies") in this group, along with their goals and budget allocations.")
            }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let g = editing {
            name = g.name
            sort = g.sort
        } else {
            sort = (groups.map(\.sort).max() ?? -1) + 1
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let g = editing {
            g.name = trimmed
            g.sort = sort
        } else {
            let g = CategoryGroupModel(name: trimmed, sort: sort)
            context.insert(g)
        }
        try? context.save()
        dismiss()
    }
}

private struct CategoryEditor: View {
    let editing: CategoryModel?
    let defaultGroup: CategoryGroupModel?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CategoryGroupModel.sort) private var groups: [CategoryGroupModel]

    @State private var name: String = ""
    @State private var sort: Int = 0
    @State private var groupID: UUID?
    @State private var didLoad = false

    @State private var hasGoal: Bool = false
    @State private var goalType: GoalType = .monthlyAmount
    @State private var goalAmountText: String = ""
    @State private var goalDate: Date = Date()

    @State private var showDeleteAlert = false
    @State private var showMergeSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)
                    Picker("Group", selection: $groupID) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(groups) { g in
                            Text(g.name).tag(Optional(g.id))
                        }
                    }
                    Stepper("Order: \(sort)", value: $sort, in: 0...99)
                }

                Section("Goal (optional)") {
                    Toggle("Set a goal", isOn: $hasGoal)
                    if hasGoal {
                        Picker("Type", selection: $goalType) {
                            Text("Monthly Amount").tag(GoalType.monthlyAmount)
                            Text("By Target Date").tag(GoalType.byDateTarget)
                            Text("Savings Target").tag(GoalType.savingsTarget)
                        }
                        #if canImport(UIKit)
                        TextField("Target Amount", text: $goalAmountText)
                            .keyboardType(.decimalPad)
                        #else
                        TextField("Target Amount", text: $goalAmountText)
                        #endif
                        if goalType == .byDateTarget {
                            DatePicker("Target Date", selection: $goalDate, displayedComponents: .date)
                        }
                    }
                }

                if editing != nil {
                    Section {
                        Button {
                            showMergeSheet = true
                        } label: {
                            Label("Merge Into…", systemImage: "arrow.triangle.merge")
                        }
                        .disabled((groups.flatMap(\.categories).count) < 2)
                        Button("Delete Category", role: .destructive) { showDeleteAlert = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .alert("Delete Category?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let c = editing {
                        context.delete(c)
                        try? context.save()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                let txCount = editing?.transactions.count ?? 0
                Text("Transactions stay but become uncategorized. \(txCount) transaction(s) affected. Goals and budget allocations for this category will be removed.")
            }
            .sheet(isPresented: $showMergeSheet) {
                if let source = editing {
                    MergeCategorySheet(source: source) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && groupID != nil
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let cat = editing {
            name = cat.name
            sort = cat.sort
            groupID = cat.group?.id
            if let goal = cat.goals.first {
                hasGoal = true
                goalType = goal.type
                goalAmountText = formatPlain(goal.targetAmount)
                goalDate = goal.targetDate ?? Date()
            }
        } else if let dg = defaultGroup {
            groupID = dg.id
            let siblings = dg.categories
            sort = (siblings.map(\.sort).max() ?? -1) + 1
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let group = groups.first(where: { $0.id == groupID })
        let amount = Decimal(string: goalAmountText) ?? 0
        let targetDate: Date? = goalType == .byDateTarget ? goalDate : nil

        let target: CategoryModel
        if let cat = editing {
            cat.name = trimmed
            cat.sort = sort
            cat.group = group
            target = cat
        } else {
            let cat = CategoryModel(name: trimmed, sort: sort, group: group)
            context.insert(cat)
            target = cat
        }

        if hasGoal {
            if let goal = target.goals.first {
                goal.type = goalType
                goal.targetAmount = amount
                goal.targetDate = targetDate
            } else {
                let goal = GoalModel(type: goalType, targetAmount: amount, targetDate: targetDate, category: target)
                context.insert(goal)
            }
        } else {
            for goal in target.goals {
                context.delete(goal)
            }
        }

        try? context.save()
        dismiss()
    }
}

private struct MergeCategorySheet: View {
    let source: CategoryModel
    let onMerged: () -> Void

    @Environment(BudgetEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var categories: [CategoryModel]

    @State private var targetID: UUID?
    @State private var showConfirm = false

    private var candidates: [CategoryModel] {
        categories
            .filter { $0.id != source.id }
            .sorted(by: { $0.name < $1.name })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Merge \(source.name) into…") {
                    Picker("Target", selection: $targetID) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(candidates) { cat in
                            Text(cat.name).tag(Optional(cat.id))
                        }
                    }
                }

                Section {
                    Text("\(source.transactions.count) transaction(s) and \(source.allocations.count) budget allocation(s) will be re-pointed at the target. The source category and its goal (if any) will be deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Merge Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") { showConfirm = true }
                        .disabled(targetID == nil)
                }
            }
            .alert("Merge?", isPresented: $showConfirm) {
                Button("Merge", role: .destructive) {
                    if let target = categories.first(where: { $0.id == targetID }) {
                        engine.merge(source, into: target, context: context)
                    }
                    dismiss()
                    onMerged()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This cannot be undone. \"\(source.name)\" will be deleted.")
            }
        }
    }
}

// MARK: - Account Editor

private struct AccountEditor: View {
    let editing: AccountModel?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: AccountType = .checking
    @State private var balanceText: String = ""
    @State private var currencyCode: String = "USD"
    @State private var didLoad = false
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    #if canImport(UIKit)
                    TextField("Balance", text: $balanceText)
                        .keyboardType(type.isAsset ? .decimalPad : .numbersAndPunctuation)
                    #else
                    TextField("Balance", text: $balanceText)
                    #endif
                    #if canImport(UIKit)
                    TextField("Currency Code", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                    #else
                    TextField("Currency Code", text: $currencyCode)
                    #endif
                }

                if !type.isAsset {
                    Section {
                        Text("For credit cards and loans, enter the balance as a negative number (e.g. -450).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if editing != nil {
                    Section {
                        Button("Delete Account", role: .destructive) { showDeleteAlert = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Account" : "Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .alert("Delete Account?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let a = editing {
                        context.delete(a)
                        try? context.save()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                let txCount = editing?.transactions.count ?? 0
                Text(txCount == 0
                     ? "This account has no transactions."
                     : "This will also delete \(txCount) transaction(s) in this account.")
            }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let a = editing {
            name = a.name
            type = a.type
            balanceText = formatPlain(a.balance)
            currencyCode = a.currencyCode
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let balance = Decimal(string: balanceText) ?? 0
        let code = currencyCode.trimmingCharacters(in: .whitespaces).isEmpty ? "USD" : currencyCode
        if let a = editing {
            a.name = trimmed
            a.type = type
            a.balance = balance
            a.currencyCode = code
        } else {
            let a = AccountModel(name: trimmed, type: type, balance: balance, currencyCode: code)
            context.insert(a)
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Scheduled Editor

private struct ScheduledEditor: View {
    let editing: ScheduledItemModel?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [AccountModel]
    @Query private var categories: [CategoryModel]

    @State private var kind: ScheduledKind = .bill
    @State private var name: String = ""
    @State private var isInflow: Bool = false
    @State private var amountText: String = ""
    @State private var nextDate: Date = Date()
    @State private var intervalDays: Int = 30
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var didLoad = false
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Scheduled Item") {
                    Picker("Kind", selection: $kind) {
                        Text("Bill").tag(ScheduledKind.bill)
                        Text("Paycheck").tag(ScheduledKind.paycheck)
                        Text("Subscription").tag(ScheduledKind.subscription)
                    }
                    TextField("Name", text: $name)
                    Picker("Type", selection: $isInflow) {
                        Text("Outflow").tag(false)
                        Text("Inflow").tag(true)
                    }
                    .pickerStyle(.segmented)
                    #if canImport(UIKit)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    #else
                    TextField("Amount", text: $amountText)
                    #endif
                }

                Section("Schedule") {
                    DatePicker("Next Date", selection: $nextDate, displayedComponents: .date)
                    Stepper("Every \(intervalDays) day\(intervalDays == 1 ? "" : "s")", value: $intervalDays, in: 1...365)
                }

                Section("Defaults") {
                    Picker("Account", selection: $accountID) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(accounts.sorted(by: { $0.name < $1.name })) { acc in
                            Text(acc.name).tag(Optional(acc.id))
                        }
                    }
                    Picker("Category", selection: $categoryID) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(categories.sorted(by: { $0.name < $1.name })) { cat in
                            Text(cat.name).tag(Optional(cat.id))
                        }
                    }
                }

                if editing != nil {
                    Section {
                        Button("Delete Scheduled Item", role: .destructive) { showDeleteAlert = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Scheduled" : "Edit Scheduled")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .alert("Delete Scheduled Item?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let s = editing {
                        context.delete(s)
                        try? context.save()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Already-posted transactions stay; only the recurring rule is removed.")
            }
        }
    }

    private var canSave: Bool {
        guard accountID != nil, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let amount = Decimal(string: amountText) ?? 0
        return amount > 0
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let s = editing else { return }
        kind = s.kind
        name = s.name
        isInflow = s.amount >= 0
        amountText = formatPlain(abs(s.amount))
        nextDate = s.nextDate
        intervalDays = s.intervalDays
        accountID = s.account?.id
        categoryID = s.category?.id
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let magnitude = Decimal(string: amountText) ?? 0
        let signed = isInflow ? magnitude : -magnitude
        let account = accounts.first { $0.id == accountID }
        let category = categories.first { $0.id == categoryID }

        if let s = editing {
            s.kind = kind
            s.name = trimmed
            s.amount = signed
            s.nextDate = nextDate
            s.intervalDays = intervalDays
            s.account = account
            s.category = category
        } else {
            let s = ScheduledItemModel(
                kind: kind,
                name: trimmed,
                amount: signed,
                nextDate: nextDate,
                intervalDays: intervalDays,
                account: account,
                category: category
            )
            context.insert(s)
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Formatting

private func currency(_ d: Decimal) -> String {
    let n = NSDecimalNumber(decimal: d)
    let f = NumberFormatter()
    f.numberStyle = .currency
    return f.string(from: n) ?? "$0"
}

private func formatPlain(_ d: Decimal) -> String {
    let n = NSDecimalNumber(decimal: d)
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 2
    f.minimumFractionDigits = 0
    return f.string(from: n) ?? "0"
}
