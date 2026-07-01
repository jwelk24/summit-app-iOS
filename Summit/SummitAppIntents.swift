import Foundation
import AppIntents
import SwiftData

// MARK: - Shared helpers

@MainActor
private func openSummitContext() -> ModelContext? {
    guard let container = try? ModelContainer(
        for: SummitSharedStore.schema,
        configurations: [SummitSharedStore.makeConfiguration()]
    ) else { return nil }
    return ModelContext(container)
}

private func currencyString(_ value: Double, code: String, fractionDigits: Int = 2) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = code
    f.maximumFractionDigits = fractionDigits
    return f.string(from: NSNumber(value: value)) ?? "\(value)"
}

// MARK: - Log Expense

struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Expense"
    static let description = IntentDescription("Quickly record an expense in Summit.")

    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Merchant") var merchant: String
    @Parameter(title: "Category", default: nil) var category: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: SummitSharedStore.schema,
                configurations: [SummitSharedStore.makeConfiguration()]
            )
        } catch {
            return .result(dialog: "I couldn't open Summit's data right now.")
        }
        let context = ModelContext(container)

        let accounts = (try? context.fetch(FetchDescriptor<AccountModel>())) ?? []
        guard let account = accounts.first(where: { $0.type == .checking }) ?? accounts.first else {
            return .result(dialog: "I couldn't find a Summit account to log this against.")
        }

        var matchedCategory: CategoryModel?
        if let categoryName = category?.trimmingCharacters(in: .whitespacesAndNewlines), !categoryName.isEmpty {
            let cats = (try? context.fetch(FetchDescriptor<CategoryModel>())) ?? []
            matchedCategory = cats.first { $0.name.caseInsensitiveCompare(categoryName) == .orderedSame }
        }

        let tx = TransactionModel(
            date: Date(),
            amount: Decimal(-abs(amount)),
            merchant: merchant,
            cleared: false,
            account: account,
            category: matchedCategory
        )
        context.insert(tx)
        try? context.save()

        SummitSnapshotWriter.write(context: context)

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = account.currencyCode
        formatter.maximumFractionDigits = 2
        let amountStr = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
        let categoryNote = matchedCategory.map { " in \($0.name)" } ?? ""
        return .result(dialog: "Logged \(amountStr) at \(merchant)\(categoryNote).")
    }
}

// MARK: - Record Income

struct LogIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Income"
    static let description = IntentDescription("Record income or a deposit in Summit. Handy for a \"when I get paid\" automation.")

    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Source", default: "Income") var source: String
    @Parameter(title: "Category", default: nil) var category: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = openSummitContext() else {
            return .result(dialog: "I couldn't open Summit's data right now.")
        }

        let accounts = (try? context.fetch(FetchDescriptor<AccountModel>())) ?? []
        guard let account = accounts.first(where: { $0.type == .checking }) ?? accounts.first else {
            return .result(dialog: "I couldn't find a Summit account to record this in.")
        }

        var matchedCategory: CategoryModel?
        if let categoryName = category?.trimmingCharacters(in: .whitespacesAndNewlines), !categoryName.isEmpty {
            let cats = (try? context.fetch(FetchDescriptor<CategoryModel>())) ?? []
            matchedCategory = cats.first { $0.name.caseInsensitiveCompare(categoryName) == .orderedSame }
        }

        let tx = TransactionModel(
            date: Date(),
            amount: Decimal(abs(amount)),
            merchant: source,
            cleared: false,
            account: account,
            category: matchedCategory
        )
        context.insert(tx)
        try? context.save()
        SummitSnapshotWriter.write(context: context)

        let amountStr = currencyString(abs(amount), code: account.currencyCode)
        return .result(dialog: "Recorded \(amountStr) from \(source).")
    }
}

// MARK: - Spent Today

struct SpentTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Spent Today"
    static let description = IntentDescription("Hear how much you've spent so far today. Returns the amount for use in automations.")

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let context = openSummitContext() else {
            return .result(value: 0, dialog: IntentDialog("I couldn't open Summit's data right now."))
        }

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let outflows = (try? context.fetch(FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.date >= start && $0.amount < 0 }
        ))) ?? []

        let total = outflows.reduce(Decimal.zero) { $0 + (-$1.amount) }
        let totalDouble = NSDecimalNumber(decimal: total).doubleValue
        let code = (try? context.fetch(FetchDescriptor<AccountModel>()))?.first?.currencyCode ?? "USD"
        let amountStr = currencyString(totalDouble, code: code, fractionDigits: 2)

        let dialog = outflows.isEmpty
            ? "You haven't spent anything yet today."
            : "You've spent \(amountStr) today across \(outflows.count) transaction\(outflows.count == 1 ? "" : "s")."
        return .result(value: totalDouble, dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - Budget Remaining

struct BudgetRemainingIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Budget Remaining"
    static let description = IntentDescription("Hear how much is left in this month's budget.")

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snap = SummitSnapshot.load() else {
            return .result(dialog: "Open Summit once so I can read your latest budget.")
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = snap.currencyCode
        formatter.maximumFractionDigits = 0
        let remainingStr = formatter.string(from: NSNumber(value: snap.budgetRemaining)) ?? "$0"
        if snap.budgetRemaining < 0 {
            let overStr = formatter.string(from: NSNumber(value: -snap.budgetRemaining)) ?? "$0"
            return .result(dialog: "You're \(overStr) over budget for \(snap.monthLabel).")
        }
        return .result(dialog: "You have \(remainingStr) left for \(snap.monthLabel).")
    }
}

// MARK: - Net Worth

struct NetWorthIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Net Worth"
    static let description = IntentDescription("Hear your current net worth from Summit.")

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snap = SummitSnapshot.load() else {
            return .result(dialog: "Open Summit once so I can read your accounts.")
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = snap.currencyCode
        formatter.maximumFractionDigits = 0
        let nwStr = formatter.string(from: NSNumber(value: snap.netWorth)) ?? "$0"
        return .result(dialog: "Your net worth is \(nwStr).")
    }
}

// MARK: - Shortcuts registration

struct SummitAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BudgetRemainingIntent(),
            phrases: [
                "What's my budget in \(.applicationName)",
                "How much budget do I have left in \(.applicationName)",
                "Check my \(.applicationName) budget"
            ],
            shortTitle: "Budget Left",
            systemImageName: "wallet.pass.fill"
        )
        AppShortcut(
            intent: NetWorthIntent(),
            phrases: [
                "What's my net worth in \(.applicationName)",
                "Check my \(.applicationName) net worth"
            ],
            shortTitle: "Net Worth",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log expense in \(.applicationName)",
                "Add expense to \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: LogIncomeIntent(),
            phrases: [
                "Record income in \(.applicationName)",
                "Add income to \(.applicationName)"
            ],
            shortTitle: "Record Income",
            systemImageName: "arrow.down.circle.fill"
        )
        AppShortcut(
            intent: SpentTodayIntent(),
            phrases: [
                "How much have I spent today in \(.applicationName)",
                "Check my \(.applicationName) spending today"
            ],
            shortTitle: "Spent Today",
            systemImageName: "creditcard.fill"
        )
    }
}
