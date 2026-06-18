import Foundation
import SwiftData
import WidgetKit

struct SummitSnapshot: Codable {
    struct AccountSummary: Codable, Identifiable, Hashable {
        let id: UUID
        let name: String
        let typeRawValue: String
        let balance: Double
    }

    struct BillSummary: Codable, Identifiable, Hashable {
        let id: UUID
        let name: String
        let amount: Double
        let date: Date
    }

    let lastUpdated: Date
    let currencyCode: String
    let totalAssets: Double
    let totalLiabilities: Double
    let accounts: [AccountSummary]
    let monthLabel: String
    let budgetAssigned: Double
    let budgetSpent: Double
    let upcomingBills: [BillSummary]

    var netWorth: Double { totalAssets - totalLiabilities }
    var budgetRemaining: Double { budgetAssigned - budgetSpent }
    var budgetUsedFraction: Double {
        guard budgetAssigned > 0 else { return 0 }
        return min(1.0, max(0.0, budgetSpent / budgetAssigned))
    }

    static let appGroupID = "group.com.welker.Summit"
    static let snapshotFilename = "SummitSnapshot.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename)
    }

    static func load() -> SummitSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SummitSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = SummitSnapshot.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
enum SummitSnapshotWriter {
    static func write(context: ModelContext) {
        let snap = build(context: context)
        try? snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func build(context: ModelContext) -> SummitSnapshot {
        let accounts = (try? context.fetch(FetchDescriptor<AccountModel>())) ?? []
        let txs = (try? context.fetch(FetchDescriptor<TransactionModel>())) ?? []
        let scheduled = (try? context.fetch(FetchDescriptor<ScheduledItemModel>())) ?? []

        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1

        let bmDescriptor = FetchDescriptor<BudgetMonthModel>(
            predicate: #Predicate { $0.year == year && $0.month == month }
        )
        let budgetMonth = (try? context.fetch(bmDescriptor))?.first

        var totalAssets: Decimal = 0
        var totalLiabilities: Decimal = 0
        for a in accounts {
            if a.type.isAsset { totalAssets += a.balance }
            else { totalLiabilities += abs(a.balance) }
        }

        let accountSummaries: [SummitSnapshot.AccountSummary] = accounts
            .sorted { $0.name < $1.name }
            .map { acct in
                SummitSnapshot.AccountSummary(
                    id: acct.id,
                    name: acct.name,
                    typeRawValue: acct.type.rawValue,
                    balance: NSDecimalNumber(decimal: acct.balance).doubleValue
                )
            }

        let assignedTotal = budgetMonth?.allocations.reduce(Decimal.zero) { $0 + $1.amount } ?? 0
        let spentTotal = txs
            .filter { $0.amount < 0 &&
                cal.component(.year, from: $0.date) == year &&
                cal.component(.month, from: $0.date) == month
            }
            .reduce(Decimal.zero) { $0 + abs($1.amount) }

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        var monthDateComps = DateComponents()
        monthDateComps.year = year
        monthDateComps.month = month
        monthDateComps.day = 1
        let monthLabel = monthFormatter.string(from: cal.date(from: monthDateComps) ?? now)

        let in30 = cal.date(byAdding: .day, value: 30, to: now) ?? now
        let startOfToday = cal.startOfDay(for: now)
        let upcoming: [SummitSnapshot.BillSummary] = scheduled
            .filter { $0.amount < 0 && $0.nextDate >= startOfToday && $0.nextDate <= in30 }
            .sorted { $0.nextDate < $1.nextDate }
            .prefix(6)
            .map { item in
                SummitSnapshot.BillSummary(
                    id: item.id,
                    name: item.name,
                    amount: NSDecimalNumber(decimal: item.amount).doubleValue,
                    date: item.nextDate
                )
            }

        let currency = accounts.first?.currencyCode ?? "USD"

        return SummitSnapshot(
            lastUpdated: Date(),
            currencyCode: currency,
            totalAssets: NSDecimalNumber(decimal: totalAssets).doubleValue,
            totalLiabilities: NSDecimalNumber(decimal: totalLiabilities).doubleValue,
            accounts: accountSummaries,
            monthLabel: monthLabel,
            budgetAssigned: NSDecimalNumber(decimal: assignedTotal).doubleValue,
            budgetSpent: NSDecimalNumber(decimal: spentTotal).doubleValue,
            upcomingBills: upcoming
        )
    }
}
