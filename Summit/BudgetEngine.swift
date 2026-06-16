import Foundation
import SwiftData

@Observable
final class BudgetEngine {
    var selectedYear: Int
    var selectedMonth: Int

    init(reference: Date = Date()) {
        let comps = Calendar.current.dateComponents([.year, .month], from: reference)
        self.selectedYear = comps.year ?? 2026
        self.selectedMonth = comps.month ?? 1
    }

    // MARK: - Pure calculations

    static func availableToBudget(transactions: [TransactionModel], budgetMonth: BudgetMonthModel?, year: Int, month: Int) -> Decimal {
        let cal = Calendar.current
        let inflow = transactions
            .filter { $0.amount > 0 && cal.component(.year, from: $0.date) == year && cal.component(.month, from: $0.date) == month }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let assigned = budgetMonth?.allocations.reduce(Decimal.zero) { $0 + $1.amount } ?? 0
        let carry = budgetMonth?.carryover ?? 0
        return inflow + carry - assigned
    }

    static func assigned(for category: CategoryModel, in budgetMonth: BudgetMonthModel?) -> Decimal {
        budgetMonth?.allocations.first(where: { $0.category?.id == category.id })?.amount ?? 0
    }

    static func activity(for category: CategoryModel, year: Int, month: Int) -> Decimal {
        let cal = Calendar.current
        let txTotal = category.transactions
            .filter { tx in
                tx.splits.isEmpty &&
                cal.component(.year, from: tx.date) == year &&
                cal.component(.month, from: tx.date) == month
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let splitTotal = category.splits
            .filter { split in
                guard let tx = split.transaction else { return false }
                return cal.component(.year, from: tx.date) == year &&
                       cal.component(.month, from: tx.date) == month
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return txTotal + splitTotal
    }

    static func available(for category: CategoryModel, in budgetMonth: BudgetMonthModel?, year: Int, month: Int) -> Decimal {
        assigned(for: category, in: budgetMonth) + activity(for: category, year: year, month: month)
    }

    // MARK: - Mutations

    @discardableResult
    func ensureMonth(year: Int, month: Int, context: ModelContext) -> BudgetMonthModel {
        let descriptor = FetchDescriptor<BudgetMonthModel>(
            predicate: #Predicate { $0.year == year && $0.month == month }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let new = BudgetMonthModel(year: year, month: month)
        context.insert(new)
        try? context.save()
        return new
    }

    func assign(_ amount: Decimal, to category: CategoryModel, in budgetMonth: BudgetMonthModel, context: ModelContext) {
        if let existing = budgetMonth.allocations.first(where: { $0.category?.id == category.id }) {
            existing.amount += amount
        } else {
            let alloc = BudgetAllocationModel(amount: amount, category: category, month: budgetMonth)
            context.insert(alloc)
        }
        try? context.save()
    }

    func setAssigned(_ amount: Decimal, to category: CategoryModel, in budgetMonth: BudgetMonthModel, context: ModelContext) {
        if let existing = budgetMonth.allocations.first(where: { $0.category?.id == category.id }) {
            existing.amount = amount
        } else {
            let alloc = BudgetAllocationModel(amount: amount, category: category, month: budgetMonth)
            context.insert(alloc)
        }
        try? context.save()
    }

    // MARK: - Credit Card Reservation

    func applyCreditCardReservation(for tx: TransactionModel, context: ModelContext) {
        guard let account = tx.account, account.type == .creditCard, tx.amount < 0 else { return }
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month], from: tx.date)
        guard let year = c.year, let month = c.month else { return }
        let bm = ensureMonth(year: year, month: month, context: context)
        guard let payment = paymentCategory(for: account, context: context) else { return }

        if tx.splits.isEmpty, let spending = tx.category, spending.id != payment.id {
            transferAllocation(abs(tx.amount), from: spending, to: payment, in: bm, context: context)
        } else {
            for split in tx.splits {
                guard let spending = split.category, spending.id != payment.id else { continue }
                transferAllocation(abs(split.amount), from: spending, to: payment, in: bm, context: context)
            }
        }
        try? context.save()
    }

    func paymentCategory(for account: AccountModel, context: ModelContext) -> CategoryModel? {
        let descriptor = FetchDescriptor<CategoryModel>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first { $0.linkedAccount?.id == account.id }
    }

    @discardableResult
    func ensurePaymentCategory(for account: AccountModel, context: ModelContext) -> CategoryModel? {
        if let existing = paymentCategory(for: account, context: context) { return existing }
        let groupName = "Credit Card Payments"
        let groupDescriptor = FetchDescriptor<CategoryGroupModel>(
            predicate: #Predicate { $0.name == groupName }
        )
        let group: CategoryGroupModel
        if let existing = try? context.fetch(groupDescriptor).first {
            group = existing
        } else {
            let allGroupsDescriptor = FetchDescriptor<CategoryGroupModel>()
            let all = (try? context.fetch(allGroupsDescriptor)) ?? []
            let nextSort = (all.map(\.sort).max() ?? -1) + 1
            group = CategoryGroupModel(name: groupName, sort: nextSort)
            context.insert(group)
        }
        let cat = CategoryModel(name: account.name, sort: 0, group: group, linkedAccount: account)
        context.insert(cat)
        try? context.save()
        return cat
    }

    private func transferAllocation(_ amount: Decimal, from source: CategoryModel, to target: CategoryModel, in bm: BudgetMonthModel, context: ModelContext) {
        if let alloc = bm.allocations.first(where: { $0.category?.id == source.id }) {
            alloc.amount -= amount
        } else {
            let alloc = BudgetAllocationModel(amount: -amount, category: source, month: bm)
            context.insert(alloc)
        }
        if let alloc = bm.allocations.first(where: { $0.category?.id == target.id }) {
            alloc.amount += amount
        } else {
            let alloc = BudgetAllocationModel(amount: amount, category: target, month: bm)
            context.insert(alloc)
        }
    }

    func coverOverspending(from source: CategoryModel, to target: CategoryModel, amount: Decimal, in budgetMonth: BudgetMonthModel, context: ModelContext) {
        let sourceAlloc = budgetMonth.allocations.first(where: { $0.category?.id == source.id })
        let sourceAssigned = sourceAlloc?.amount ?? 0
        let newSource = max(0, sourceAssigned - amount)
        let delta = sourceAssigned - newSource
        sourceAlloc?.amount = newSource
        if let targetAlloc = budgetMonth.allocations.first(where: { $0.category?.id == target.id }) {
            targetAlloc.amount += delta
        } else {
            let alloc = BudgetAllocationModel(amount: delta, category: target, month: budgetMonth)
            context.insert(alloc)
        }
        try? context.save()
    }

    func rollToNextMonth(from current: BudgetMonthModel, transactions: [TransactionModel], categories: [CategoryModel], context: ModelContext) {
        let unassigned = Self.availableToBudget(transactions: transactions, budgetMonth: current, year: current.year, month: current.month)
        let overspent = categories.reduce(Decimal.zero) { partial, cat in
            let avail = Self.available(for: cat, in: current, year: current.year, month: current.month)
            return partial + min(0, avail)
        }
        let carry = max(0, unassigned) + overspent
        let next = nextYearMonth(year: current.year, month: current.month)
        let nextMonth = ensureMonth(year: next.year, month: next.month, context: context)
        nextMonth.carryover = carry
        selectedYear = next.year
        selectedMonth = next.month
        try? context.save()
    }

    private func nextYearMonth(year: Int, month: Int) -> (year: Int, month: Int) {
        var m = month + 1
        var y = year
        if m > 12 { m = 1; y += 1 }
        return (y, m)
    }

    // MARK: - Scheduled items

    func postScheduled(_ item: ScheduledItemModel, context: ModelContext) {
        postOne(item, context: context)
        try? context.save()
    }

    func postAllDue(_ items: [ScheduledItemModel], context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        for item in items {
            var safety = 0
            while item.nextDate < today, safety < 365 {
                postOne(item, context: context)
                safety += 1
            }
        }
        try? context.save()
    }

    private func postOne(_ item: ScheduledItemModel, context: ModelContext) {
        let tx = TransactionModel(
            date: item.nextDate,
            amount: item.amount,
            merchant: item.name,
            memo: nil,
            cleared: false,
            account: item.account,
            category: item.category
        )
        context.insert(tx)
        if item.intervalDays > 0,
           let next = Calendar.current.date(byAdding: .day, value: item.intervalDays, to: item.nextDate) {
            item.nextDate = next
        }
    }

    // MARK: - Category merge

    func merge(_ source: CategoryModel, into target: CategoryModel, context: ModelContext) {
        guard source.id != target.id else { return }
        for tx in source.transactions {
            tx.category = target
        }
        for split in source.splits {
            split.category = target
        }
        for alloc in source.allocations {
            if let existing = target.allocations.first(where: { $0.month?.id == alloc.month?.id }) {
                existing.amount += alloc.amount
                context.delete(alloc)
            } else {
                alloc.category = target
            }
        }
        for goal in source.goals {
            context.delete(goal)
        }
        context.delete(source)
        try? context.save()
    }
}

// MARK: - Reset

extension BudgetEngine {
    @MainActor
    static func resetAllData(context: ModelContext, reference: Date = Date()) {
        deleteAll(BalanceSnapshotModel.self, in: context)
        deleteAll(TransactionSplitModel.self, in: context)
        deleteAll(TransactionModel.self, in: context)
        deleteAll(BudgetAllocationModel.self, in: context)
        deleteAll(BudgetMonthModel.self, in: context)
        deleteAll(GoalModel.self, in: context)
        deleteAll(ScheduledItemModel.self, in: context)
        deleteAll(CategoryModel.self, in: context)
        deleteAll(CategoryGroupModel.self, in: context)
        deleteAll(AccountModel.self, in: context)
        try? context.save()
        seedIfNeeded(context: context, reference: reference)
    }

    @MainActor
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        let descriptor = FetchDescriptor<T>()
        if let items = try? context.fetch(descriptor) {
            for item in items {
                context.delete(item)
            }
        }
    }
}

// MARK: - Seeding

extension BudgetEngine {
    @MainActor
    static func seedIfNeeded(context: ModelContext, reference: Date = Date()) {
        let accountCount = (try? context.fetchCount(FetchDescriptor<AccountModel>())) ?? 0
        guard accountCount == 0 else { return }

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: reference)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1

        let checking = AccountModel(name: "Checking", type: .checking, balance: 3800)
        let savings = AccountModel(name: "Savings", type: .savings, balance: 5000)
        let creditCard = AccountModel(name: "Credit Card", type: .creditCard, balance: -450)
        [checking, savings, creditCard].forEach { context.insert($0) }

        let needs = CategoryGroupModel(name: "Needs (Fixed Expenses)", sort: 0)
        let wants = CategoryGroupModel(name: "Wants (Flexible Expenses)", sort: 1)
        let savingsDebt = CategoryGroupModel(name: "Savings & Debt", sort: 2)
        let cardPayments = CategoryGroupModel(name: "Credit Card Payments", sort: 3)
        [needs, wants, savingsDebt, cardPayments].forEach { context.insert($0) }

        let creditCardCat = CategoryModel(name: creditCard.name, sort: 0, group: cardPayments, linkedAccount: creditCard)
        context.insert(creditCardCat)

        let housing = CategoryModel(name: "Housing", sort: 0, group: needs)
        let utilitiesCat = CategoryModel(name: "Utilities", sort: 1, group: needs)
        let groceries = CategoryModel(name: "Groceries", sort: 2, group: needs)
        let transportation = CategoryModel(name: "Transportation", sort: 3, group: needs)
        let insurance = CategoryModel(name: "Insurance", sort: 4, group: needs)

        let diningEntertainment = CategoryModel(name: "Dining Out & Entertainment", sort: 0, group: wants)
        let subscriptions = CategoryModel(name: "Subscriptions", sort: 1, group: wants)
        let personalCare = CategoryModel(name: "Personal Care & Clothing", sort: 2, group: wants)
        let travel = CategoryModel(name: "Vacation & Travel", sort: 3, group: wants)
        let gifts = CategoryModel(name: "Gifts & Donations", sort: 4, group: wants)

        let debtRepayment = CategoryModel(name: "Debt Repayment", sort: 0, group: savingsDebt)
        let savingsInvestments = CategoryModel(name: "Savings & Investments", sort: 1, group: savingsDebt)

        let allCategories = [
            housing, utilitiesCat, groceries, transportation, insurance,
            diningEntertainment, subscriptions, personalCare, travel, gifts,
            debtRepayment, savingsInvestments,
        ]
        allCategories.forEach { context.insert($0) }

        let goalHousing = GoalModel(type: .monthlyAmount, targetAmount: 1800, category: housing)
        let goalGroceries = GoalModel(type: .monthlyAmount, targetAmount: 500, category: groceries)
        let goalSavings = GoalModel(type: .monthlyAmount, targetAmount: 400, category: savingsInvestments)
        [goalHousing, goalGroceries, goalSavings].forEach { context.insert($0) }

        let paycheckDate = cal.date(byAdding: .day, value: 3, to: reference) ?? reference
        let housingDate = cal.date(byAdding: .day, value: 10, to: reference) ?? reference
        let utilitiesDate = cal.date(byAdding: .day, value: 15, to: reference) ?? reference

        let paycheck = ScheduledItemModel(kind: .paycheck, name: "Paycheck", amount: 2000, nextDate: paycheckDate, intervalDays: 14, account: checking)
        let housingBill = ScheduledItemModel(kind: .bill, name: "Rent", amount: -1800, nextDate: housingDate, intervalDays: 30, account: checking, category: housing)
        let utilitiesBill = ScheduledItemModel(kind: .bill, name: "Utilities", amount: -180, nextDate: utilitiesDate, intervalDays: 30, account: checking, category: utilitiesCat)
        [paycheck, housingBill, utilitiesBill].forEach { context.insert($0) }

        let tx1 = TransactionModel(date: reference, amount: 2500, merchant: "Employer", cleared: true, account: checking)
        let tx2 = TransactionModel(date: reference, amount: -120, merchant: "Whole Foods", cleared: true, account: checking, category: groceries)
        let tx3 = TransactionModel(date: reference, amount: -45, merchant: "Chipotle", cleared: true, account: checking, category: diningEntertainment)
        [tx1, tx2, tx3].forEach { context.insert($0) }

        let monthRec = BudgetMonthModel(year: year, month: month, carryover: 0)
        context.insert(monthRec)
        let allocHousing = BudgetAllocationModel(amount: 1800, category: housing, month: monthRec)
        let allocGroceries = BudgetAllocationModel(amount: 300, category: groceries, month: monthRec)
        let allocSavings = BudgetAllocationModel(amount: 400, category: savingsInvestments, month: monthRec)
        [allocHousing, allocGroceries, allocSavings].forEach { context.insert($0) }

        try? context.save()
    }
}

