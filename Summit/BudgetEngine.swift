import Combine
import Foundation

final class BudgetEngine: ObservableObject {
    @Published private(set) var accounts: [Account]
    @Published private(set) var transactions: [Transaction]
    @Published private(set) var groups: [CategoryGroup]
    @Published private(set) var categories: [Category]
    @Published private(set) var scheduled: [ScheduledItem]
    @Published private(set) var goals: [Goal]
    @Published private(set) var months: [BudgetMonth] // keep last few months

    @Published var selectedYear: Int
    @Published var selectedMonth: Int

    init(accounts: [Account], transactions: [Transaction], groups: [CategoryGroup], categories: [Category], scheduled: [ScheduledItem], goals: [Goal], months: [BudgetMonth], selectedYear: Int, selectedMonth: Int) {
        self.accounts = accounts
        self.transactions = transactions
        self.groups = groups
        self.categories = categories
        self.scheduled = scheduled
        self.goals = goals
        self.months = months
        self.selectedYear = selectedYear
        self.selectedMonth = selectedMonth
    }

    // MARK: - Budget Logic

    func availableToBudget(for year: Int, month: Int) -> Decimal {
        let inflow = transactions
            .filter { Calendar.current.component(.year, from: $0.date) == year && Calendar.current.component(.month, from: $0.date) == month && $0.amount > 0 }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let assigned = monthRecord(year: year, month: month)?.allocations.values.reduce(Decimal.zero, +) ?? 0
        let carry = monthRecord(year: year, month: month)?.carryover ?? 0
        return inflow + carry - assigned
    }

    func assign(_ amount: Decimal, to categoryId: UUID, year: Int, month: Int) {
        guard var rec = monthRecord(year: year, month: month) else { return }
        var alloc = rec.allocations[categoryId] ?? 0
        alloc += amount
        rec.allocations[categoryId] = alloc
        replaceMonth(rec)
        objectWillChange.send()
    }

    func activity(for categoryId: UUID, year: Int, month: Int) -> Decimal {
        transactions.filter { $0.categoryId == categoryId && Calendar.current.component(.year, from: $0.date) == year && Calendar.current.component(.month, from: $0.date) == month }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    func available(for categoryId: UUID, year: Int, month: Int) -> Decimal {
        let assigned = monthRecord(year: year, month: month)?.allocations[categoryId] ?? 0
        let act = activity(for: categoryId, year: year, month: month) // negative for spend
        return assigned + act
    }

    func coverOverspending(from sourceCategoryId: UUID, to targetCategoryId: UUID, amount: Decimal, year: Int, month: Int) {
        guard var rec = monthRecord(year: year, month: month) else { return }
        let sourceAssigned = rec.allocations[sourceCategoryId] ?? 0
        let newSource = max(0, sourceAssigned - amount)
        let delta = sourceAssigned - newSource
        let targetAssigned = rec.allocations[targetCategoryId] ?? 0
        rec.allocations[sourceCategoryId] = newSource
        rec.allocations[targetCategoryId] = targetAssigned + delta
        replaceMonth(rec)
        objectWillChange.send()
    }

    func rollToNextMonth(currentYear: Int, currentMonth: Int) {
        guard monthRecord(year: currentYear, month: currentMonth) != nil else { return }
        let overspent = categories.reduce(Decimal.zero) { partial, cat in
            let avail = available(for: cat.id, year: currentYear, month: currentMonth)
            return partial + min(0, avail)
        }
        let unassigned = availableToBudget(for: currentYear, month: currentMonth)
        let carry = max(0, unassigned) // simple scaffold rule
        let next = nextYearMonth(year: currentYear, month: currentMonth)
        let nextRec = BudgetMonth(id: UUID(), year: next.year, month: next.month, allocations: [:], carryover: carry + overspent)
        months.append(nextRec)
        selectedYear = next.year
        selectedMonth = next.month
    }

    // MARK: - Helpers

    func monthRecord(year: Int, month: Int) -> BudgetMonth? {
        months.first { $0.year == year && $0.month == month }
    }

    private func replaceMonth(_ newValue: BudgetMonth) {
        if let idx = months.firstIndex(where: { $0.id == newValue.id }) {
            months[idx] = newValue
        }
    }

    private func nextYearMonth(year: Int, month: Int) -> (year: Int, month: Int) {
        var m = month + 1
        var y = year
        if m > 12 { m = 1; y += 1 }
        return (y, m)
    }
}

// MARK: - Sample Data

extension BudgetEngine {
    static func sample(reference: Date = Date()) -> BudgetEngine {
        var cal = Calendar.current
        cal.timeZone = .current
        let comps = cal.dateComponents([.year, .month], from: reference)
        let year = comps.year ?? 2025
        let month = comps.month ?? 1

        let checking = Account(name: "Checking", type: .checking, balance: 3200)
        let savings = Account(name: "Savings", type: .savings, balance: 5000)

        let groupNeeds = CategoryGroup(name: "Immediate Obligations", sort: 0)
        let groupWants = CategoryGroup(name: "True Expenses", sort: 1)

        let rent = Category(groupId: groupNeeds.id, name: "Rent", sort: 0)
        let groceries = Category(groupId: groupNeeds.id, name: "Groceries", sort: 1)
        let dining = Category(groupId: groupWants.id, name: "Dining Out", sort: 0)
        let fun = Category(groupId: groupWants.id, name: "Fun Money", sort: 1)

        let goalRent = Goal(categoryId: rent.id, type: .monthlyAmount, targetAmount: 1800, targetDate: nil)
        let goalGroceries = Goal(categoryId: groceries.id, type: .monthlyAmount, targetAmount: 500, targetDate: nil)

        let paycheck = ScheduledItem(kind: .paycheck, name: "Paycheck", amount: 2500, nextDate: reference, intervalDays: 14, accountId: checking.id)
        let rentBill = ScheduledItem(kind: .bill, name: "Rent", amount: -1800, nextDate: cal.date(byAdding: .day, value: 10, to: reference)!, intervalDays: 30, accountId: checking.id)

        let txs: [Transaction] = [
            Transaction(accountId: checking.id, date: reference, amount: 2500, merchant: "Employer", memo: "", categoryId: nil, cleared: true),
            Transaction(accountId: checking.id, date: reference, amount: -120, merchant: "Whole Foods", memo: nil, categoryId: groceries.id, cleared: true),
            Transaction(accountId: checking.id, date: reference, amount: -45, merchant: "Chipotle", memo: nil, categoryId: dining.id, cleared: true)
        ]

        let monthRec = BudgetMonth(year: year, month: month, allocations: [rent.id: 1800, groceries.id: 300], carryover: 0)

        return BudgetEngine(
            accounts: [checking, savings],
            transactions: txs,
            groups: [groupNeeds, groupWants],
            categories: [rent, groceries, dining, fun],
            scheduled: [paycheck, rentBill],
            goals: [goalRent, goalGroceries],
            months: [monthRec],
            selectedYear: year,
            selectedMonth: month
        )
    }
}

