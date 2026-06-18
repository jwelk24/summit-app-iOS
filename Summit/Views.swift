import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

// MARK: - BudgetView

struct BudgetView: View {
    @Environment(BudgetEngine.self) private var engine
    @Environment(\.modelContext) private var context

    @Query private var groups: [CategoryGroupModel]
    @Query private var categories: [CategoryModel]
    @Query private var transactions: [TransactionModel]
    @Query private var months: [BudgetMonthModel]

    @State private var showingMove = false
    @State private var showingManageCategories = false
    @State private var showingRename = false

    @AppStorage("budgetTitle") private var budgetTitle: String = "Budget"

    private var budgetMonth: BudgetMonthModel? {
        months.first { $0.year == engine.selectedYear && $0.month == engine.selectedMonth }
    }

    private struct MonthEntry: Identifiable, Hashable {
        let year: Int
        let month: Int
        let date: Date
        var id: Date { date }
    }

    private var availableMonths: [MonthEntry] {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        let curY = comps.year ?? 2026
        let curM = comps.month ?? 1
        let currentMonthDate = cal.date(from: DateComponents(year: curY, month: curM, day: 1)) ?? now
        let endDate = cal.date(byAdding: .month, value: 3, to: currentMonthDate) ?? currentMonthDate

        let existingDates = months.compactMap {
            cal.date(from: DateComponents(year: $0.year, month: $0.month, day: 1))
        }
        let earliest = existingDates.min() ?? currentMonthDate
        let twelveMonthsAgo = cal.date(byAdding: .month, value: -12, to: currentMonthDate) ?? currentMonthDate
        let startDate = min(earliest, twelveMonthsAgo)

        var result: [MonthEntry] = []
        var cursor = startDate
        var safety = 0
        while cursor <= endDate, safety < 120 {
            let c = cal.dateComponents([.year, .month], from: cursor)
            result.append(MonthEntry(year: c.year ?? curY, month: c.month ?? curM, date: cursor))
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
            safety += 1
        }
        return result
    }

    private var currentMonthIndex: Int? {
        availableMonths.firstIndex { $0.year == engine.selectedYear && $0.month == engine.selectedMonth }
    }

    private func navigateMonths(_ delta: Int) {
        let months = availableMonths
        guard let i = currentMonthIndex else {
            if let entry = months.first {
                engine.selectedYear = entry.year
                engine.selectedMonth = entry.month
                _ = engine.ensureMonth(year: entry.year, month: entry.month, context: context)
            }
            return
        }
        let target = i + delta
        guard target >= 0 && target < months.count else { return }
        let entry = months[target]
        engine.selectedYear = entry.year
        engine.selectedMonth = entry.month
        _ = engine.ensureMonth(year: entry.year, month: entry.month, context: context)
    }

    private var currentMonthLabel: String {
        let cal = Calendar.current
        guard let d = cal.date(from: DateComponents(year: engine.selectedYear, month: engine.selectedMonth, day: 1)) else {
            return "\(engine.selectedMonth)/\(engine.selectedYear)"
        }
        return d.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        navigateMonths(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .disabled((currentMonthIndex ?? 0) <= 0)
                    .accessibilityIdentifier("prevMonthButton")

                    Menu {
                        ForEach(availableMonths) { entry in
                            Button {
                                engine.selectedYear = entry.year
                                engine.selectedMonth = entry.month
                                _ = engine.ensureMonth(year: entry.year, month: entry.month, context: context)
                            } label: {
                                if entry.year == engine.selectedYear && entry.month == engine.selectedMonth {
                                    Label(entry.date.formatted(.dateTime.month(.wide).year()), systemImage: "checkmark")
                                } else {
                                    Text(entry.date.formatted(.dateTime.month(.wide).year()))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentMonthLabel)
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.tint.opacity(0.15), in: Capsule())
                    }
                    .accessibilityIdentifier("monthSelector")

                    Button {
                        navigateMonths(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .disabled({
                        let idx = currentMonthIndex ?? 0
                        return idx >= availableMonths.count - 1
                    }())
                    .accessibilityIdentifier("nextMonthButton")
                    Spacer()
                }
                .padding(.horizontal)

                HStack {
                    Text("Available to Budget: \(currency(BudgetEngine.availableToBudget(transactions: transactions, budgetMonth: budgetMonth, year: engine.selectedYear, month: engine.selectedMonth)))")
                        .font(.headline)
                        .accessibilityIdentifier("availableToBudgetLabel")
                    Spacer()
                    if let aom = BudgetEngine.ageOfMoneyDays(transactions: transactions) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.clock").font(.caption2)
                            Text("Age of Money: \(aom)d").font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .accessibilityIdentifier("ageOfMoneyChip")
                    }
                }
                .padding(.horizontal)

                List {
                    ForEach(groups.sorted(by: { $0.sort < $1.sort })) { group in
                        Section(group.name) {
                            ForEach(categories.filter { $0.group?.id == group.id }.sorted(by: { $0.sort < $1.sort })) { cat in
                                CategoryRow(
                                    category: cat,
                                    budgetMonth: budgetMonth,
                                    year: engine.selectedYear,
                                    month: engine.selectedMonth
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle(budgetTitle)
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
                            let bm = budgetMonth ?? engine.ensureMonth(year: engine.selectedYear, month: engine.selectedMonth, context: context)
                            engine.autoAssignAvailable(transactions: transactions, categories: categories, budgetMonth: bm, context: context)
                        } label: {
                            Label("Auto-Assign to Goals", systemImage: "wand.and.stars")
                        }
                        .accessibilityIdentifier("autoAssignButton")

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

                        Button {
                            showingRename = true
                        } label: {
                            Label("Customize Tabs", systemImage: "rectangle.3.group")
                        }
                        .accessibilityIdentifier("customizeTabsButton")
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("budgetActionsMenu")
                }
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
            .sheet(isPresented: $showingRename) {
                CustomizeTabsView()
            }
            .accessibilityIdentifier("budgetScreen")
        }
    }
}

// MARK: - Tab customization

struct TabIdentity: Identifiable {
    let id: String
    let titleKey: String
    let iconKey: String
    let defaultTitle: String
    let defaultIcon: String
}

let tabIdentities: [TabIdentity] = [
    TabIdentity(id: "budget", titleKey: "budgetTitle", iconKey: "budgetIcon", defaultTitle: "Budget", defaultIcon: "list.bullet.rectangle"),
    TabIdentity(id: "transactions", titleKey: "transactionsTitle", iconKey: "transactionsIcon", defaultTitle: "Transactions", defaultIcon: "creditcard"),
    TabIdentity(id: "netWorth", titleKey: "netWorthTitle", iconKey: "netWorthIcon", defaultTitle: "Net Worth", defaultIcon: "chart.line.uptrend.xyaxis"),
    TabIdentity(id: "horizon", titleKey: "horizonTitle", iconKey: "horizonIcon", defaultTitle: "Horizon", defaultIcon: "mountain.2"),
    TabIdentity(id: "reports", titleKey: "reportsTitle", iconKey: "reportsIcon", defaultTitle: "Reports", defaultIcon: "chart.pie"),
]

let curatedTabIcons: [String] = [
    "list.bullet.rectangle", "list.bullet", "rectangle.stack",
    "creditcard", "wallet.pass", "banknote",
    "dollarsign.circle", "dollarsign.square", "centsign.circle",
    "chart.line.uptrend.xyaxis", "chart.bar", "chart.bar.xaxis",
    "chart.pie", "chart.dots.scatter", "chart.xyaxis.line",
    "mountain.2", "mountain.2.fill", "globe.americas",
    "house", "building.columns", "briefcase",
    "cart", "bag", "gift",
    "calendar", "calendar.badge.clock", "clock",
    "flag", "target", "star",
    "bookmark", "bell", "sparkles",
    "folder", "doc.text", "tray.full",
    "arrow.up.right", "arrow.down.right", "arrow.up.arrow.down",
    "arrow.left.arrow.right", "leaf", "bolt",
]

struct CustomizeTabsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tabIdentities) { identity in
                        NavigationLink {
                            TabAppearanceEditor(identity: identity)
                        } label: {
                            TabRow(identity: identity)
                        }
                    }
                } header: {
                    Text("Tabs")
                } footer: {
                    Text("Tap a tab to change its label or icon. The new name appears both on the bottom bar and at the top of that screen.")
                }
            }
            .navigationTitle("Customize Tabs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct TabRow: View {
    let identity: TabIdentity

    @AppStorage private var title: String
    @AppStorage private var icon: String

    init(identity: TabIdentity) {
        self.identity = identity
        self._title = AppStorage(wrappedValue: identity.defaultTitle, identity.titleKey)
        self._icon = AppStorage(wrappedValue: identity.defaultIcon, identity.iconKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 32, height: 32)
                .foregroundStyle(.tint)
            Text(title)
            Spacer()
        }
    }
}

private struct TabAppearanceEditor: View {
    let identity: TabIdentity

    @Environment(\.dismiss) private var dismiss

    @AppStorage private var title: String
    @AppStorage private var icon: String

    @State private var draftTitle: String = ""
    @State private var draftIcon: String = ""
    @State private var didLoad = false

    init(identity: TabIdentity) {
        self.identity = identity
        self._title = AppStorage(wrappedValue: identity.defaultTitle, identity.titleKey)
        self._icon = AppStorage(wrappedValue: identity.defaultIcon, identity.iconKey)
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 56), spacing: 8)]

    var body: some View {
        Form {
            Section("Label") {
                TextField(identity.defaultTitle, text: $draftTitle)
            }

            Section("Icon") {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(curatedTabIcons, id: \.self) { name in
                        Button { draftIcon = name } label: {
                            Image(systemName: name)
                                .font(.title3)
                                .frame(width: 48, height: 48)
                                .background(
                                    draftIcon == name ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .foregroundStyle(draftIcon == name ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button("Reset to Default") {
                    draftTitle = identity.defaultTitle
                    draftIcon = identity.defaultIcon
                }
            }
        }
        .navigationTitle("Customize \(identity.defaultTitle)")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
                    title = trimmed.isEmpty ? identity.defaultTitle : trimmed
                    icon = draftIcon
                    dismiss()
                }
            }
        }
        .onAppear {
            if !didLoad {
                draftTitle = title
                draftIcon = icon
                didLoad = true
            }
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
    @Environment(BudgetEngine.self) private var engine
    @Environment(\.modelContext) private var context

    @Query private var allMonths: [BudgetMonthModel]

    let category: CategoryModel
    let budgetMonth: BudgetMonthModel?
    let year: Int
    let month: Int

    @State private var isEditing = false
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let assigned = BudgetEngine.assigned(for: category, in: budgetMonth)
        let activity = BudgetEngine.activity(for: category, year: year, month: month)
        let available = BudgetEngine.available(for: category, in: budgetMonth, year: year, month: month)

        HStack(spacing: 10) {
            goalIndicator(assigned: assigned, available: available)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                Text("Activity \(currency(activity))  ·  Available \(currency(available))")
                    .font(.caption)
                    .foregroundStyle(available < 0 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            }
            Spacer()
            if isEditing {
                #if canImport(UIKit)
                TextField("0", text: $editText)
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 70)
                    .submitLabel(.done)
                    .onSubmit { commit() }
                #else
                TextField("0", text: $editText)
                    .focused($isFocused)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 70)
                    .onSubmit { commit() }
                #endif
            } else {
                Text(currency(assigned))
                    .monospacedDigit()
                    .frame(minWidth: 70, alignment: .trailing)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { startEditing(assigned: assigned) }
                    .contextMenu { quickAssignMenu(assigned: assigned, available: available) }
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && isEditing { commit() }
        }
    }

    @ViewBuilder
    private func quickAssignMenu(assigned: Decimal, available: Decimal) -> some View {
        let last = BudgetEngine.lastMonthAssigned(for: category, currentYear: year, currentMonth: month, allMonths: allMonths)
        let avg = BudgetEngine.averageAssigned(for: category, monthsBack: 3, currentYear: year, currentMonth: month, allMonths: allMonths)
        let goal = category.goals.first

        Button {
            commitAmount(last)
        } label: {
            Label("Match Last Month  \(currency(last))", systemImage: "arrow.uturn.backward")
        }
        .disabled(last == 0)

        Button {
            commitAmount(avg)
        } label: {
            Label("3-Month Average  \(currency(avg))", systemImage: "chart.bar")
        }
        .disabled(avg == 0)

        if let goal {
            let target = goal.targetAmount
            Button {
                commitAmount(target)
            } label: {
                Label("Set to Goal  \(currency(target))", systemImage: "target")
            }

            let underfunded: Decimal = {
                switch goal.type {
                case .monthlyAmount: return max(0, target - assigned)
                case .savingsTarget, .byDateTarget: return max(0, target - max(0, available))
                }
            }()
            if underfunded > 0 {
                Button {
                    commitAmount(assigned + underfunded)
                } label: {
                    Label("Fund Underfunded  +\(currency(underfunded))", systemImage: "plus.circle")
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            commitAmount(0)
        } label: {
            Label("Clear", systemImage: "xmark.circle")
        }
    }

    private func commitAmount(_ amount: Decimal) {
        let bm = budgetMonth ?? engine.ensureMonth(year: year, month: month, context: context)
        engine.setAssigned(amount, to: category, in: bm, context: context)
    }

    @ViewBuilder
    private func goalIndicator(assigned: Decimal, available: Decimal) -> some View {
        if let goal = category.goals.first {
            let progress = computeProgress(goal: goal, assigned: assigned, available: available)
            let clamped = min(1.0, max(0.0, progress))
            let color: Color = progress >= 1.0 ? .green : .accentColor
            ZStack {
                Circle().stroke(Color.gray.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if progress >= 1.0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 22, height: 22)
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }

    private func computeProgress(goal: GoalModel, assigned: Decimal, available: Decimal) -> Double {
        let target = NSDecimalNumber(decimal: goal.targetAmount).doubleValue
        guard target > 0 else { return 0 }
        switch goal.type {
        case .monthlyAmount:
            return NSDecimalNumber(decimal: assigned).doubleValue / target
        case .savingsTarget, .byDateTarget:
            return NSDecimalNumber(decimal: max(0, available)).doubleValue / target
        }
    }

    private func startEditing(assigned: Decimal) {
        editText = formatPlain(assigned)
        isEditing = true
        DispatchQueue.main.async { isFocused = true }
    }

    private func commit() {
        defer {
            isEditing = false
            isFocused = false
        }
        let amount = Decimal(string: editText) ?? 0
        let bm = budgetMonth ?? engine.ensureMonth(year: year, month: month, context: context)
        engine.setAssigned(amount, to: category, in: bm, context: context)
    }
}

// MARK: - TransactionsView

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TransactionModel.date, order: .reverse) private var transactions: [TransactionModel]
    @Query private var accounts: [AccountModel]
    @Query private var categories: [CategoryModel]

    @AppStorage("transactionsTitle") private var transactionsTitle: String = "Transactions"

    @State private var showingNew = false
    @State private var editing: TransactionModel?
    @State private var showingImporter = false
    @State private var importMessage: String?
    @State private var showingReceiptScanner = false

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
            .navigationTitle(transactionsTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingNew = true
                        } label: {
                            Label("New Transaction", systemImage: "plus")
                        }
                        .accessibilityIdentifier("addTransactionButton")

                        Button {
                            showingReceiptScanner = true
                        } label: {
                            Label("Scan Receipt…", systemImage: "doc.text.viewfinder")
                        }
                        .accessibilityIdentifier("scanReceiptButton")

                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import CSV", systemImage: "square.and.arrow.down")
                        }
                        .accessibilityIdentifier("importCSVButton")
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNew) {
                TransactionEditor(editing: nil)
            }
            .sheet(item: $editing) { tx in
                TransactionEditor(editing: tx)
            }
            .sheet(isPresented: $showingReceiptScanner) {
                ReceiptScannerView()
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.commaSeparatedText, .text, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
            .alert("Import Result", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("OK", role: .cancel) { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(transactions[index])
        }
        try? context.save()
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = "Could not access file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else {
                importMessage = "Could not read file as text."
                return
            }
            let res = BudgetEngine.importCSV(content, accounts: accounts, categories: categories, context: context)
            var lines: [String] = []
            lines.append("Imported \(res.imported), skipped \(res.skipped).")
            if !res.errors.isEmpty {
                let firstFew = res.errors.prefix(3).joined(separator: "\n")
                lines.append("\n\(firstFew)")
                if res.errors.count > 3 {
                    lines.append("…and \(res.errors.count - 3) more.")
                }
            }
            importMessage = lines.joined(separator: "\n")
        case .failure(let err):
            importMessage = err.localizedDescription
        }
    }
}

private struct TransactionRow: View {
    let transaction: TransactionModel

    var body: some View {
        HStack {
            if let color = flagColor(transaction.flagColor) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                HStack(spacing: 6) {
                    Text(transaction.date, style: .date)
                    if let category = transaction.category {
                        Text("·")
                        Text(category.name)
                    } else if !transaction.splits.isEmpty {
                        Text("·")
                        Text("Split")
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

private struct SplitDraft: Identifiable, Equatable {
    let id: UUID
    var amountText: String
    var categoryID: UUID?
    var memo: String
}

private struct TransactionEditor: View {
    let editing: TransactionModel?
    var defaultAccount: AccountModel? = nil

    @Environment(BudgetEngine.self) private var engine
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
    @State private var flagColorName: String? = nil
    @State private var didLoad: Bool = false
    @State private var splits: [SplitDraft] = []

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

                if splits.isEmpty {
                    Picker("Category", selection: $categoryID) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(categories.sorted(by: { $0.name < $1.name })) { cat in
                            Text(cat.name).tag(Optional(cat.id))
                        }
                    }
                }

                TextField("Memo (optional)", text: $memo)

                Toggle("Cleared", isOn: $cleared)

                Picker("Flag", selection: $flagColorName) {
                    Text("None").tag(String?.none)
                    ForEach(flagOptions, id: \.name) { option in
                        HStack {
                            Circle().fill(option.color).frame(width: 12, height: 12)
                            Text(option.label)
                        }
                        .tag(Optional(option.name))
                    }
                }

                Section {
                    if splits.isEmpty {
                        Button {
                            startSplit()
                        } label: {
                            Label("Split Across Categories", systemImage: "rectangle.split.3x1")
                        }
                    } else {
                        ForEach($splits) { $split in
                            VStack(alignment: .leading, spacing: 6) {
                                Picker("Category", selection: $split.categoryID) {
                                    Text("Uncategorized").tag(UUID?.none)
                                    ForEach(categories.sorted(by: { $0.name < $1.name })) { cat in
                                        Text(cat.name).tag(Optional(cat.id))
                                    }
                                }
                                #if canImport(UIKit)
                                TextField("Amount", text: $split.amountText)
                                    .keyboardType(.decimalPad)
                                #else
                                TextField("Amount", text: $split.amountText)
                                #endif
                                TextField("Memo (optional)", text: $split.memo)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            splits.remove(atOffsets: offsets)
                        }

                        Button {
                            splits.append(SplitDraft(id: UUID(), amountText: "", categoryID: nil, memo: ""))
                        } label: {
                            Label("Add Split", systemImage: "plus.circle")
                        }

                        HStack {
                            Text("Splits sum")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(currency(splitsSum))
                                .font(.caption)
                                .foregroundStyle(splitMismatch ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                        }
                        if splitMismatch {
                            Text("Splits must sum to \(currency(signedTotal)).")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }

                        Button("Remove Splits", role: .destructive) {
                            splits.removeAll()
                        }
                    }
                } header: {
                    Text(splits.isEmpty ? "Optional" : "Splits")
                }
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

    private var signedTotal: Decimal {
        let magnitude = Decimal(string: amountText) ?? 0
        return isInflow ? magnitude : -magnitude
    }

    private var splitsSum: Decimal {
        splits.reduce(Decimal.zero) { $0 + (Decimal(string: $1.amountText) ?? 0) }
    }

    private var splitMismatch: Bool {
        !splits.isEmpty && splitsSum != signedTotal
    }

    private var canSave: Bool {
        guard accountID != nil, !merchant.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let magnitude = Decimal(string: amountText) ?? 0
        if magnitude <= 0 { return false }
        if !splits.isEmpty {
            if splits.contains(where: { Decimal(string: $0.amountText) == nil }) { return false }
            if splitMismatch { return false }
        }
        return true
    }

    private func startSplit() {
        let total = signedTotal
        splits = [
            SplitDraft(id: UUID(), amountText: formatSigned(total), categoryID: categoryID, memo: ""),
            SplitDraft(id: UUID(), amountText: "", categoryID: nil, memo: "")
        ]
        categoryID = nil
    }

    private func formatSigned(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: n) ?? "0"
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let tx = editing {
            isInflow = tx.amount >= 0
            amountText = formatPlain(abs(tx.amount))
            merchant = tx.merchant
            memo = tx.memo ?? ""
            date = tx.date
            accountID = tx.account?.id
            categoryID = tx.category?.id
            cleared = tx.cleared
            flagColorName = tx.flagColor
            splits = tx.splits.map { existing in
                SplitDraft(
                    id: existing.id,
                    amountText: formatSigned(existing.amount),
                    categoryID: existing.category?.id,
                    memo: existing.memo ?? ""
                )
            }
        } else if let preselect = defaultAccount {
            accountID = preselect.id
        }
    }

    private func save() {
        let signed = signedTotal
        let account = accounts.first { $0.id == accountID }
        let category = splits.isEmpty ? categories.first { $0.id == categoryID } : nil
        let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)

        let target: TransactionModel
        let isNew: Bool
        if let tx = editing {
            tx.amount = signed
            tx.merchant = merchant
            tx.memo = trimmedMemo.isEmpty ? nil : trimmedMemo
            tx.date = date
            tx.account = account
            tx.category = category
            tx.cleared = cleared
            tx.flagColor = flagColorName
            for old in tx.splits {
                context.delete(old)
            }
            target = tx
            isNew = false
        } else {
            let tx = TransactionModel(
                date: date,
                amount: signed,
                merchant: merchant,
                memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                cleared: cleared,
                flagColor: flagColorName,
                account: account,
                category: category
            )
            context.insert(tx)
            target = tx
            isNew = true
        }

        for draft in splits {
            let amount = Decimal(string: draft.amountText) ?? 0
            let splitCategory = categories.first { $0.id == draft.categoryID }
            let trimmed = draft.memo.trimmingCharacters(in: .whitespaces)
            let split = TransactionSplitModel(
                amount: amount,
                memo: trimmed.isEmpty ? nil : trimmed,
                transaction: target,
                category: splitCategory
            )
            context.insert(split)
        }

        try? context.save()

        if isNew {
            engine.applyCreditCardReservation(for: target, context: context)
        }

        dismiss()
    }

}

// MARK: - NetWorthView

struct NetWorthView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [AccountModel]
    @Query private var transactions: [TransactionModel]

    @AppStorage("netWorthTitle") private var netWorthTitle: String = "Net Worth"

    @State private var showingNew = false
    @State private var editing: AccountModel?
    @State private var selectedAccountIDs: Set<UUID>? = nil
    @State private var timeRange: NetWorthTimeRange = .threeMonths
    @State private var chartMode: NetWorthChartMode = .combined
    @State private var showingFilter = false

    // Plaid state
    @State private var linkedPlaidItems: [PlaidKeychain.StoredItem] = PlaidKeychain.allItems()
    @State private var plaidLinkSession: PlaidLinkSession?
    @State private var pendingMerge: PendingMergeContext?
    @State private var showingConnections = false
    @State private var creatingPlaidLink = false
    @State private var syncingItemId: String?
    @State private var plaidStatus: String?
    @State private var plaidStatusIsError = false

    private struct PendingMergeContext: Identifiable {
        let id = UUID()
        let item: PlaidKeychain.StoredItem
        let pending: [PlaidSyncService.PendingPlaidAccount]
    }

    private var filteredAccounts: [AccountModel] {
        guard let ids = selectedAccountIDs else { return accounts }
        return accounts.filter { ids.contains($0.id) }
    }
    private var filteredAssets: [AccountModel] {
        filteredAccounts.filter { $0.type.isAsset }
    }
    private var filteredLiabilities: [AccountModel] {
        filteredAccounts.filter { !$0.type.isAsset }
    }
    private var totalAssets: Decimal { filteredAssets.reduce(.zero) { $0 + $1.balance } }
    private var totalLiabilities: Decimal { filteredLiabilities.reduce(.zero) { $0 + abs($1.balance) } }
    private var netWorth: Decimal { totalAssets - totalLiabilities }

    private var allAssets: [AccountModel] {
        accounts.filter { $0.type.isAsset }.sorted { $0.name < $1.name }
    }
    private var allLiabilities: [AccountModel] {
        accounts.filter { !$0.type.isAsset }.sorted { $0.name < $1.name }
    }

    private var filterLabel: String {
        guard let ids = selectedAccountIDs else { return "All accounts" }
        if ids.isEmpty { return "No accounts selected" }
        return "\(ids.count) of \(accounts.count) accounts"
    }

    private var rangeAgoDate: Date {
        let cal = Calendar.current
        if let days = timeRange.days,
           let d = cal.date(byAdding: .day, value: -days, to: Date()) {
            return d
        }
        let earliest = filteredAccounts
            .flatMap { $0.transactions.map(\.date) + $0.snapshots.map(\.date) }
            .min()
        return earliest ?? (cal.date(byAdding: .year, value: -1, to: Date()) ?? Date())
    }

    private var rangeLabel: String {
        switch timeRange {
        case .oneMonth: return "1 month ago"
        case .threeMonths: return "3 months ago"
        case .sixMonths: return "6 months ago"
        case .oneYear: return "1 year ago"
        case .all: return "start"
        }
    }

    private var deltaVsPast: (delta: Decimal, percent: Double?)? {
        guard !filteredAccounts.isEmpty else { return nil }
        let past = netWorthAt(rangeAgoDate, accounts: filteredAccounts)
        let now = netWorthAt(Date(), accounts: filteredAccounts)
        let delta = now - past
        let pastDouble = NSDecimalNumber(decimal: past).doubleValue
        let deltaDouble = NSDecimalNumber(decimal: delta).doubleValue
        let pct: Double? = abs(pastDouble) > 0.01 ? deltaDouble / abs(pastDouble) * 100 : nil
        return (delta, pct)
    }

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
                    if let d = deltaVsPast {
                        HStack(spacing: 6) {
                            Image(systemName: d.delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            Text(currency(d.delta))
                            if let pct = d.percent {
                                Text(String(format: "(%@%.1f%%)", pct >= 0 ? "+" : "", pct))
                            }
                            Text("vs \(rangeLabel)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(d.delta >= 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.red))
                        .accessibilityIdentifier("netWorthDeltaLabel")
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

                Section {
                    HStack {
                        Picker("Range", selection: $timeRange) {
                            ForEach(NetWorthTimeRange.allCases) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .pickerStyle(.segmented)

                        Menu {
                            Picker("View", selection: $chartMode) {
                                ForEach(NetWorthChartMode.allCases) { m in
                                    Label(m.rawValue, systemImage: m.icon).tag(m)
                                }
                            }
                        } label: {
                            Image(systemName: chartMode.icon)
                                .frame(width: 28, height: 28)
                        }
                        .accessibilityIdentifier("chartModeMenu")
                    }

                    NetWorthChart(
                        accounts: filteredAccounts,
                        transactions: transactions,
                        range: timeRange,
                        mode: chartMode
                    )
                    .frame(height: 240)

                    Button {
                        showingFilter = true
                    } label: {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(filterLabel)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("filterAccountsButton")
                } header: {
                    Text("Trend")
                }

                if !linkedPlaidItems.isEmpty {
                    Section("Linked Banks") {
                        ForEach(linkedPlaidItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.institutionName ?? item.itemId)
                                    Text("Linked \(item.linkedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if syncingItemId == item.itemId {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button("Sync") {
                                        Task { await syncPlaidItem(item) }
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { unlinkPlaidItem(item) } label: {
                                    Label("Unlink", systemImage: "trash")
                                }
                            }
                        }
                        Button {
                            Task {
                                for item in linkedPlaidItems {
                                    await syncPlaidItem(item)
                                }
                            }
                        } label: {
                            Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(syncingItemId != nil)
                    }
                }

                if !allAssets.isEmpty {
                    Section("Assets") {
                        ForEach(allAssets) { acc in
                            NavigationLink {
                                AccountRegisterView(account: acc)
                            } label: {
                                accountRow(acc)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { editing = acc } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(.blue)
                            }
                        }
                    }
                }

                if !allLiabilities.isEmpty {
                    Section("Liabilities") {
                        ForEach(allLiabilities) { acc in
                            NavigationLink {
                                AccountRegisterView(account: acc)
                            } label: {
                                accountRow(acc)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { editing = acc } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(.blue)
                            }
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
            .navigationTitle(netWorthTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await startPlaidLink() }
                        } label: {
                            Label(creatingPlaidLink ? "Preparing…" : "Link with Plaid…", systemImage: "link.badge.plus")
                        }
                        .disabled(creatingPlaidLink)

                        Button { showingNew = true } label: {
                            Label("Add Manually…", systemImage: "square.and.pencil")
                        }

                        if !linkedPlaidItems.isEmpty {
                            Divider()
                            Button { showingConnections = true } label: {
                                Label("Manage Linked Banks…", systemImage: "gearshape")
                            }
                        }
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addAccountButton")
                }
            }
            .sheet(isPresented: $showingNew) { AccountEditor(editing: nil) }
            .sheet(item: $editing) { acc in AccountEditor(editing: acc) }
            .sheet(isPresented: $showingFilter) {
                AccountFilterSheet(selectedIDs: $selectedAccountIDs)
            }
            .sheet(item: $plaidLinkSession) { session in
                PlaidLinkSheet(session: session, onResult: handlePlaidLinkResult)
            }
            .sheet(item: $pendingMerge) { ctx in
                PlaidMergePickerView(
                    plaidItemId: ctx.item.itemId,
                    pendingAccounts: ctx.pending
                ) {
                    Task { await syncPlaidItem(ctx.item) }
                }
            }
            .sheet(isPresented: $showingConnections) {
                NavigationStack {
                    PlaidConnectionsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingConnections = false }
                            }
                        }
                }
                .onDisappear { linkedPlaidItems = PlaidKeychain.allItems() }
            }
            .alert("Plaid", isPresented: Binding(get: { plaidStatus != nil }, set: { if !$0 { plaidStatus = nil } })) {
                Button("OK") { plaidStatus = nil }
            } message: {
                Text(plaidStatus ?? "")
            }
        }
    }

    // MARK: - Plaid actions

    private func startPlaidLink() async {
        creatingPlaidLink = true
        defer { creatingPlaidLink = false }
        do {
            let response = try await PlaidAPI.createLinkToken()
            guard let hostedURL = URL(string: response.hostedLinkUrl),
                  let redirect = response.redirectUri.flatMap(URL.init(string:)) else {
                showPlaidError("Backend returned an invalid link URL.")
                return
            }
            plaidLinkSession = PlaidLinkSession(hostedLinkURL: hostedURL, redirectURL: redirect)
        } catch {
            showPlaidError("Couldn't start Plaid Link: \(error.localizedDescription)")
        }
    }

    private func handlePlaidLinkResult(_ result: Result<String, PlaidLinkError>) {
        plaidLinkSession = nil
        switch result {
        case .success(let publicToken):
            Task { await exchangeAndPrepareMerge(publicToken: publicToken) }
        case .failure(.cancelled):
            return
        case .failure(let err):
            showPlaidError(err.localizedDescription)
        }
    }

    private func exchangeAndPrepareMerge(publicToken: String) async {
        do {
            let exchange = try await PlaidAPI.exchangePublicToken(publicToken)
            let stored = PlaidKeychain.StoredItem(
                itemId: exchange.itemId,
                accessToken: exchange.accessToken,
                institutionName: nil,
                linkedAt: .now
            )
            try PlaidKeychain.saveItem(stored)
            linkedPlaidItems = PlaidKeychain.allItems()

            let service = PlaidSyncService(context: context)
            let pending = try await service.peekAccounts(for: stored)
            // If there are no manual accounts to potentially merge into, just
            // sync directly — but still pop the picker if there are multiple
            // new Plaid accounts so the user sees what was added.
            let unlinkedManuals = try service.unlinkedManualAccounts()
            if pending.contains(where: { !$0.alreadyLinked }) && !unlinkedManuals.isEmpty {
                pendingMerge = PendingMergeContext(item: stored, pending: pending)
            } else {
                await syncPlaidItem(stored)
            }
        } catch {
            showPlaidError("Link exchange failed: \(error.localizedDescription)")
        }
    }

    private func syncPlaidItem(_ item: PlaidKeychain.StoredItem) async {
        syncingItemId = item.itemId
        defer { syncingItemId = nil }
        do {
            let service = PlaidSyncService(context: context)
            let result = try await service.syncAll(for: item)
            plaidStatus = "Synced \(result.accounts) acct · tx +\(result.transactionsAdded) ~\(result.transactionsModified) · holdings \(result.holdings) · inv-tx \(result.investmentTransactions) · liab \(result.liabilities)"
            plaidStatusIsError = false
            linkedPlaidItems = PlaidKeychain.allItems()
        } catch {
            showPlaidError("Sync failed: \(error.localizedDescription)")
        }
    }

    private func unlinkPlaidItem(_ item: PlaidKeychain.StoredItem) {
        do {
            try PlaidKeychain.deleteItem(itemId: item.itemId)
            linkedPlaidItems = PlaidKeychain.allItems()
        } catch {
            showPlaidError("Couldn't remove: \(error.localizedDescription)")
        }
    }

    private func showPlaidError(_ message: String) {
        plaidStatus = message
        plaidStatusIsError = true
    }

    private func accountRow(_ acc: AccountModel) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(acc.name)
                Text(acc.type.displayName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(currency(acc.balance))
                .monospacedDigit()
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

struct HorizonView: View {
    @Environment(BudgetEngine.self) private var engine
    @Environment(\.modelContext) private var context

    @Query private var accounts: [AccountModel]
    @Query private var scheduled: [ScheduledItemModel]

    @AppStorage("horizonTitle") private var horizonTitle: String = "Horizon"

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
            .navigationTitle(horizonTitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !due.isEmpty {
                        Button("Post All Due") {
                            engine.postAllDue(scheduled, context: context)
                        }
                        .accessibilityIdentifier("postAllDueButton")
                    }
                    NavigationLink {
                        CashFlowForecastView()
                    } label: {
                        Label("Forecast", systemImage: "chart.xyaxis.line")
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

    @Environment(BudgetEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: AccountType = .checking
    @State private var balanceText: String = ""
    @State private var currencyCode: String = "USD"
    @State private var didLoad = false
    @State private var showDeleteAlert = false

    @State private var showingNewSnapshot = false
    @State private var editingSnapshot: BalanceSnapshotModel?

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

                if let acc = editing {
                    Section {
                        let snaps = acc.snapshots.sorted(by: { $0.date > $1.date })
                        if snaps.isEmpty {
                            Text("No snapshots yet. Snapshots are point-in-time balances used to anchor the net-worth chart when transaction history is incomplete.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snaps) { snap in
                                Button { editingSnapshot = snap } label: {
                                    HStack {
                                        Text(snap.date, style: .date)
                                        Spacer()
                                        Text(currency(snap.balance))
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                for i in offsets {
                                    context.delete(snaps[i])
                                }
                                try? context.save()
                            }
                        }
                        Button {
                            showingNewSnapshot = true
                        } label: {
                            Label("Add Snapshot", systemImage: "plus.circle")
                                .foregroundStyle(.tint)
                        }
                    } header: {
                        Text("Balance History")
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
            .sheet(isPresented: $showingNewSnapshot) {
                if let acc = editing {
                    SnapshotEditor(account: acc, editing: nil)
                }
            }
            .sheet(item: $editingSnapshot) { snap in
                if let acc = editing {
                    SnapshotEditor(account: acc, editing: snap)
                }
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
        let target: AccountModel
        if let a = editing {
            a.name = trimmed
            a.type = type
            a.balance = balance
            a.currencyCode = code
            target = a
        } else {
            let a = AccountModel(name: trimmed, type: type, balance: balance, currencyCode: code)
            context.insert(a)
            target = a
        }
        try? context.save()
        if target.type == .creditCard {
            engine.ensurePaymentCategory(for: target, context: context)
        }
        dismiss()
    }
}

// MARK: - Account Register

struct AccountRegisterView: View {
    let account: AccountModel

    @Environment(\.modelContext) private var context

    @State private var editingAccount: Bool = false
    @State private var showingNewTransaction = false
    @State private var editingTransaction: TransactionModel?
    @State private var showingReconcile = false

    private var rows: [(transaction: TransactionModel, balanceAfter: Decimal)] {
        let sorted = account.transactions.sorted { $0.date > $1.date }
        var result: [(TransactionModel, Decimal)] = []
        var running = account.balance
        for tx in sorted {
            result.append((tx, running))
            running -= tx.amount
        }
        return result
    }

    private var clearedCount: Int { account.transactions.filter { $0.cleared }.count }
    private var unclearedCount: Int { account.transactions.filter { !$0.cleared }.count }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Current Balance").font(.headline)
                    Spacer()
                    Text(currency(account.balance))
                        .font(.title3).bold()
                        .monospacedDigit()
                }
                HStack {
                    Text("\(clearedCount) cleared · \(unclearedCount) uncleared")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showingReconcile = true
                    } label: {
                        Label("Reconcile", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("reconcileButton")
                }
            }

            Section("Transactions") {
                if rows.isEmpty {
                    Text("No transactions yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.transaction.id) { row in
                        Button { editingTransaction = row.transaction } label: {
                            registerRow(row.transaction, balanceAfter: row.balanceAfter)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(rows[index].transaction)
                        }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { editingAccount = true } label: {
                    Label("Edit Account", systemImage: "info.circle")
                }
                .accessibilityIdentifier("editAccountButton")
                Button { showingNewTransaction = true } label: {
                    Label("Add Transaction", systemImage: "plus")
                }
                .accessibilityIdentifier("addAccountTransactionButton")
            }
        }
        .sheet(isPresented: $editingAccount) {
            AccountEditor(editing: account)
        }
        .sheet(isPresented: $showingNewTransaction) {
            TransactionEditor(editing: nil, defaultAccount: account)
        }
        .sheet(item: $editingTransaction) { tx in
            TransactionEditor(editing: tx, defaultAccount: nil)
        }
        .sheet(isPresented: $showingReconcile) {
            ReconcileSheet(account: account)
        }
    }

    private func registerRow(_ tx: TransactionModel, balanceAfter: Decimal) -> some View {
        HStack {
            if let color = flagColor(tx.flagColor) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: tx.cleared ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundStyle(tx.cleared ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                    Text(tx.merchant)
                }
                HStack(spacing: 6) {
                    Text(tx.date, style: .date)
                    if let cat = tx.category {
                        Text("·")
                        Text(cat.name)
                    } else if !tx.splits.isEmpty {
                        Text("·")
                        Text("Split")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(currency(tx.amount))
                    .monospacedDigit()
                    .foregroundStyle(tx.amount < 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.green))
                Text(currency(balanceAfter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Reconcile

private struct ReconcileSheet: View {
    let account: AccountModel

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var bankBalanceText: String = ""
    @State private var pendingDelta: Decimal?
    @State private var showConfirm = false

    private var entered: Decimal? { Decimal(string: bankBalanceText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Look at the current balance shown by your bank or card issuer. Enter it below — Summit will mark everything cleared if it matches, or offer to add a Reconciliation Adjustment if it doesn't.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #if canImport(UIKit)
                    TextField("Current Balance", text: $bankBalanceText)
                        .keyboardType(.numbersAndPunctuation)
                    #else
                    TextField("Current Balance", text: $bankBalanceText)
                    #endif
                } header: {
                    Text("Reconcile \(account.name)")
                }

                if let delta = pendingDelta {
                    Section("Difference") {
                        HStack {
                            Text("Summit shows").foregroundStyle(.secondary)
                            Spacer()
                            Text(currency(account.balance)).monospacedDigit()
                        }
                        HStack {
                            Text("You entered").foregroundStyle(.secondary)
                            Spacer()
                            Text(currency(entered ?? 0)).monospacedDigit()
                        }
                        HStack {
                            Text("Adjustment").bold()
                            Spacer()
                            Text(currency(delta))
                                .monospacedDigit()
                                .foregroundStyle(delta >= 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.red))
                        }
                    }
                }
            }
            .navigationTitle("Reconcile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pendingDelta == nil ? "Next" : "Apply") {
                        if pendingDelta == nil {
                            evaluate()
                        } else {
                            apply()
                        }
                    }
                    .disabled(entered == nil)
                }
            }
        }
    }

    private func evaluate() {
        guard let entered else { return }
        let delta = entered - account.balance
        if delta == 0 {
            markAllCleared()
            try? context.save()
            dismiss()
        } else {
            pendingDelta = delta
        }
    }

    private func apply() {
        guard let entered, let delta = pendingDelta else { return }
        let adjustment = TransactionModel(
            date: Date(),
            amount: delta,
            merchant: "Reconciliation Adjustment",
            memo: nil,
            cleared: true,
            account: account,
            category: nil
        )
        context.insert(adjustment)
        account.balance = entered
        markAllCleared()
        try? context.save()
        dismiss()
    }

    private func markAllCleared() {
        for tx in account.transactions where !tx.cleared {
            tx.cleared = true
        }
    }
}

// MARK: - Snapshot Editor

private struct SnapshotEditor: View {
    let account: AccountModel
    let editing: BalanceSnapshotModel?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = Date()
    @State private var balanceText: String = ""
    @State private var didLoad = false
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Snapshot") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    #if canImport(UIKit)
                    TextField("Balance", text: $balanceText)
                        .keyboardType(.numbersAndPunctuation)
                    #else
                    TextField("Balance", text: $balanceText)
                    #endif
                }

                Section {
                    Text("\(account.name) was worth this amount on the selected date. The chart will use the most recent snapshot before a given date as its anchor, then layer transactions on top.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if editing != nil {
                    Section {
                        Button("Delete Snapshot", role: .destructive) { showDeleteAlert = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Snapshot" : "Edit Snapshot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { save() }
                        .disabled(Decimal(string: balanceText) == nil)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .alert("Delete Snapshot?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let s = editing {
                        context.delete(s)
                        try? context.save()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The chart will fall back to deriving balance from current value and transactions.")
            }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let s = editing {
            date = s.date
            balanceText = formatPlain(s.balance)
        }
    }

    private func save() {
        guard let balance = Decimal(string: balanceText) else { return }
        if let s = editing {
            s.date = date
            s.balance = balance
        } else {
            let s = BalanceSnapshotModel(date: date, balance: balance, account: account)
            context.insert(s)
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

// MARK: - Net Worth Helpers

private func balanceAt(_ date: Date, for account: AccountModel) -> Decimal {
    let snaps = account.snapshots.sorted { $0.date < $1.date }
    let anchorSnap = snaps.last(where: { $0.date <= date })
    if let snap = anchorSnap {
        let txs = account.transactions.filter { $0.date > snap.date && $0.date <= date }
        return snap.balance + txs.reduce(Decimal.zero) { $0 + $1.amount }
    } else {
        let txs = account.transactions.filter { $0.date > date }
        return account.balance - txs.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

private func netWorthAt(_ date: Date, accounts: [AccountModel]) -> Decimal {
    accounts.reduce(Decimal.zero) { partial, acc in
        let b = balanceAt(date, for: acc)
        return partial + (acc.type.isAsset ? b : -abs(b))
    }
}

// MARK: - Net Worth Chart

private enum NetWorthTimeRange: String, CaseIterable, Identifiable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .oneMonth: return 30
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .oneYear: return 365
        case .all: return nil
        }
    }
}

private enum NetWorthChartMode: String, CaseIterable, Identifiable {
    case combined = "Net Worth"
    case perAccount = "By Account"
    case assetsLiabilities = "Assets vs Liabilities"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .combined: return "chart.line.uptrend.xyaxis"
        case .perAccount: return "rectangle.split.3x1"
        case .assetsLiabilities: return "chart.bar"
        }
    }
}

private struct ChartSeriesPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let series: String
}

private struct NetWorthChart: View {
    let accounts: [AccountModel]
    let transactions: [TransactionModel]
    let range: NetWorthTimeRange
    let mode: NetWorthChartMode

    @State private var rawSelectedDate: Date?

    private var rangeBounds: (start: Date, end: Date) {
        let now = Date()
        if let days = range.days,
           let start = Calendar.current.date(byAdding: .day, value: -days, to: now) {
            return (start, now)
        }
        let earliest = accounts
            .flatMap { $0.transactions.map(\.date) + $0.snapshots.map(\.date) }
            .min()
        let fallback = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        return (earliest ?? fallback, now)
    }

    private var sampleInterval: Calendar.Component {
        switch range {
        case .oneMonth, .threeMonths: return .day
        case .sixMonths, .oneYear: return .weekOfYear
        case .all: return .month
        }
    }

    private func sampleDates(in start: Date, _ end: Date) -> [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        var current = cal.startOfDay(for: start)
        let stop = cal.startOfDay(for: end)
        var safety = 0
        while current <= stop, safety < 2000 {
            dates.append(current)
            guard let next = cal.date(byAdding: sampleInterval, value: 1, to: current) else { break }
            current = next
            safety += 1
        }
        if dates.last != end {
            dates.append(end)
        }
        return dates
    }

    private var combinedSeries: [ChartSeriesPoint] {
        let (start, end) = rangeBounds
        let dates = sampleDates(in: start, end)
        return dates.map { date in
            let total = netWorthAt(date, accounts: accounts)
            return ChartSeriesPoint(date: date, value: NSDecimalNumber(decimal: total).doubleValue, series: "Net Worth")
        }
    }

    private var perAccountSeries: [ChartSeriesPoint] {
        let (start, end) = rangeBounds
        let dates = sampleDates(in: start, end)
        var result: [ChartSeriesPoint] = []
        for acc in accounts {
            for date in dates {
                let b = balanceAt(date, for: acc)
                let signed = acc.type.isAsset ? b : -abs(b)
                result.append(ChartSeriesPoint(date: date, value: NSDecimalNumber(decimal: signed).doubleValue, series: acc.name))
            }
        }
        return result
    }

    private var assetsLiabilitiesSeries: [ChartSeriesPoint] {
        let (start, end) = rangeBounds
        let dates = sampleDates(in: start, end)
        var result: [ChartSeriesPoint] = []
        for date in dates {
            let assets = accounts.filter { $0.type.isAsset }
                .reduce(Decimal.zero) { $0 + balanceAt(date, for: $1) }
            let liabilities = accounts.filter { !$0.type.isAsset }
                .reduce(Decimal.zero) { $0 + abs(balanceAt(date, for: $1)) }
            result.append(ChartSeriesPoint(date: date, value: NSDecimalNumber(decimal: assets).doubleValue, series: "Assets"))
            result.append(ChartSeriesPoint(date: date, value: NSDecimalNumber(decimal: -liabilities).doubleValue, series: "Liabilities"))
        }
        return result
    }

    private var activeSeries: [ChartSeriesPoint] {
        switch mode {
        case .combined: return combinedSeries
        case .perAccount: return perAccountSeries
        case .assetsLiabilities: return assetsLiabilitiesSeries
        }
    }

    private func scrubReadout(at date: Date) -> [(series: String, value: Double, date: Date)] {
        let data = activeSeries
        guard !data.isEmpty else { return [] }
        let bySeries = Dictionary(grouping: data, by: \.series)
        var readouts: [(String, Double, Date)] = []
        for (name, points) in bySeries {
            let sorted = points.sorted { $0.date < $1.date }
            let nearest = sorted.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
            if let n = nearest {
                readouts.append((name, n.value, n.date))
            }
        }
        return readouts.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        let data = activeSeries
        if accounts.isEmpty {
            placeholder("Select at least one account to see a trend.")
        } else if data.count <= 1 {
            placeholder("Not enough history yet to show a trend.")
        } else {
            Chart {
                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Series", point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    if mode == .combined || mode == .assetsLiabilities {
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Balance", point.value)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(by: .value("Series", point.series))
                        .opacity(0.18)
                    }
                }

                if let raw = rawSelectedDate {
                    RuleMark(x: .value("Selected", raw))
                        .foregroundStyle(Color.gray.opacity(0.4))
                        .annotation(position: .top, alignment: .center, spacing: 0) {
                            scrubAnnotation(at: raw)
                        }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let n = value.as(Double.self) {
                            Text(compactCurrencyString(n))
                        }
                    }
                }
            }
            .chartXSelection(value: $rawSelectedDate)
        }
    }

    @ViewBuilder
    private func scrubAnnotation(at date: Date) -> some View {
        let readouts = scrubReadout(at: date)
        if !readouts.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if let first = readouts.first {
                    Text(first.date, format: .dateTime.day().month().year())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(readouts, id: \.series) { r in
                    HStack(spacing: 6) {
                        Text(r.series).font(.caption2)
                        Text(currency(Decimal(r.value))).font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 2)
        }
    }

    @ViewBuilder
    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }

    private func compactCurrencyString(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let abs = Swift.abs(value)
        switch abs {
        case 1_000_000_000...:
            return "\(sign)$\(trimmed(abs / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)$\(trimmed(abs / 1_000_000))M"
        case 1_000...:
            return "\(sign)$\(trimmed(abs / 1_000))K"
        default:
            return "\(sign)$\(Int(abs.rounded()))"
        }
    }

    private func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

// MARK: - Account Filter Sheet

private struct AccountFilterSheet: View {
    @Binding var selectedIDs: Set<UUID>?

    @Query private var accounts: [AccountModel]
    @Environment(\.dismiss) private var dismiss

    private var allIDs: Set<UUID> { Set(accounts.map(\.id)) }

    private var effectiveSelected: Set<UUID> {
        selectedIDs ?? allIDs
    }

    private func toggle(_ id: UUID) {
        var current = effectiveSelected
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        selectedIDs = (current == allIDs) ? nil : current
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(accounts.sorted(by: { $0.name < $1.name })) { acc in
                    Button {
                        toggle(acc.id)
                    } label: {
                        HStack {
                            Image(systemName: effectiveSelected.contains(acc.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(acc.name)
                                Text(acc.type.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(currency(acc.balance))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Filter Accounts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Select All") { selectedIDs = nil }
                        Button("Deselect All") { selectedIDs = [] }
                    } label: {
                        Image(systemName: "checklist")
                    }
                }
            }
        }
    }
}

// MARK: - Reports

private struct CategorySpending: Identifiable {
    let id = UUID()
    let categoryName: String
    let amount: Double
}

private struct MonthlyFlow: Identifiable {
    let id = UUID()
    let label: String
    let income: Double
    let spending: Double
}

struct ReportsView: View {
    @Environment(BudgetEngine.self) private var engine

    @Query private var transactions: [TransactionModel]

    @AppStorage("reportsTitle") private var reportsTitle: String = "Reports"

    private var spendingByCategory: [CategorySpending] {
        let cal = Calendar.current
        let year = engine.selectedYear
        let month = engine.selectedMonth
        var totals: [String: Decimal] = [:]
        for tx in transactions where tx.amount < 0
            && cal.component(.year, from: tx.date) == year
            && cal.component(.month, from: tx.date) == month {
            if tx.splits.isEmpty {
                let name = tx.category?.name ?? "Uncategorized"
                totals[name, default: 0] += abs(tx.amount)
            } else {
                for split in tx.splits {
                    let name = split.category?.name ?? "Uncategorized"
                    totals[name, default: 0] += abs(split.amount)
                }
            }
        }
        return totals
            .map { CategorySpending(categoryName: $0.key, amount: NSDecimalNumber(decimal: $0.value).doubleValue) }
            .sorted { $0.amount > $1.amount }
    }

    private var sixMonthFlow: [MonthlyFlow] {
        let cal = Calendar.current
        let now = Date()
        var result: [MonthlyFlow] = []
        for offset in stride(from: 5, through: 0, by: -1) {
            guard let monthDate = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
            let comps = cal.dateComponents([.year, .month], from: monthDate)
            guard let y = comps.year, let m = comps.month else { continue }
            var income: Decimal = 0
            var spending: Decimal = 0
            for tx in transactions where cal.component(.year, from: tx.date) == y && cal.component(.month, from: tx.date) == m {
                if tx.amount > 0 { income += tx.amount }
                else { spending += abs(tx.amount) }
            }
            let label = monthDate.formatted(.dateTime.month(.abbreviated))
            result.append(MonthlyFlow(
                label: label,
                income: NSDecimalNumber(decimal: income).doubleValue,
                spending: NSDecimalNumber(decimal: spending).doubleValue
            ))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Spending This Month") {
                    let data = spendingByCategory
                    if data.isEmpty {
                        Text("No spending recorded this month yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(data) { item in
                            BarMark(
                                x: .value("Amount", item.amount),
                                y: .value("Category", item.categoryName)
                            )
                            .foregroundStyle(Color.accentColor)
                            .annotation(position: .trailing) {
                                Text(currency(Decimal(item.amount)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let n = value.as(Double.self) {
                                        Text(n, format: .currency(code: "USD"))
                                    }
                                }
                            }
                        }
                        .frame(height: max(220, CGFloat(data.count) * 28))
                    }
                }

                Section("Income vs Spending (6 months)") {
                    let flows = sixMonthFlow
                    Chart {
                        ForEach(flows) { flow in
                            BarMark(
                                x: .value("Month", flow.label),
                                y: .value("Amount", flow.income)
                            )
                            .foregroundStyle(by: .value("Type", "Income"))
                            .position(by: .value("Type", "Income"))

                            BarMark(
                                x: .value("Month", flow.label),
                                y: .value("Amount", flow.spending)
                            )
                            .foregroundStyle(by: .value("Type", "Spending"))
                            .position(by: .value("Type", "Spending"))
                        }
                    }
                    .chartForegroundStyleScale([
                        "Income": Color.green,
                        "Spending": Color.red,
                    ])
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let n = value.as(Double.self) {
                                    Text(n, format: .currency(code: "USD"))
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                }
            }
            .navigationTitle(reportsTitle)
        }
    }
}

// MARK: - Flag colors

private let flagOptions: [(name: String, label: String, color: Color)] = [
    ("red", "Red", .red),
    ("orange", "Orange", .orange),
    ("yellow", "Yellow", .yellow),
    ("green", "Green", .green),
    ("blue", "Blue", .blue),
    ("purple", "Purple", .purple),
]

private func flagColor(_ name: String?) -> Color? {
    guard let name else { return nil }
    return flagOptions.first { $0.name == name }?.color
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
