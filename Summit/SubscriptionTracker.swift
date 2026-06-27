import Foundation
import SwiftData
import SwiftUI

// MARK: - Detection model

/// A single recurring charge inferred from the transaction log.
struct DetectedSubscription: Identifiable, Hashable {
    let id: UUID
    let merchant: String
    /// Median absolute amount across all occurrences.
    let typicalAmount: Decimal
    /// Inferred billing cadence.
    let cadence: SubscriptionCadence
    /// All transactions that contributed to the detection (most recent first).
    let occurrences: [TransactionModel]
    /// Date of the most recent occurrence.
    let lastChargeDate: Date
    /// Predicted next charge date (`lastChargeDate + cadence.intervalDays`).
    let predictedNextDate: Date
    /// Sum of every occurrence's absolute amount.
    let totalSpend: Decimal

    var occurrenceCount: Int { occurrences.count }

    static func == (lhs: DetectedSubscription, rhs: DetectedSubscription) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum SubscriptionCadence: String, CaseIterable {
    case weekly, biweekly, monthly, quarterly, yearly

    var intervalDays: Int {
        switch self {
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        case .quarterly: return 90
        case .yearly: return 365
        }
    }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Biweekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }

    /// Acceptable +/- spread when matching an observed interval to this cadence.
    var matchTolerance: Int {
        switch self {
        case .weekly: return 2
        case .biweekly: return 3
        case .monthly: return 5
        case .quarterly: return 10
        case .yearly: return 21
        }
    }
}

// MARK: - Detector

/// Pure, deterministic subscription detector. Walks the transaction log and
/// surfaces recurring outflows that have a stable amount and a recognizable
/// cadence. No external services, no fuzzy matching beyond merchant
/// normalization, no ML — just statistics on what's already there.
enum SubscriptionDetector {
    static let ignoredMerchantsKey = "subscriptionTracker.ignoredMerchants"

    /// Run detection over the supplied transactions.
    /// - Parameters:
    ///   - transactions: every transaction the user has, in any order.
    ///   - minOccurrences: minimum number of charges to consider a match.
    ///     Defaults to 3, which works well for monthly cadences over a year of
    ///     data. Drop to 2 for very recently-onboarded users.
    static func detect(
        transactions: [TransactionModel],
        minOccurrences: Int = 3,
        now: Date = .now
    ) -> [DetectedSubscription] {
        let ignored = Set(
            (UserDefaults.standard.array(forKey: ignoredMerchantsKey) as? [String]) ?? []
        )

        // 1. Only outflows with a non-empty merchant.
        let outflows = transactions.filter { $0.amount < 0 && !$0.merchant.trimmingCharacters(in: .whitespaces).isEmpty }

        // 2. Group by canonicalized merchant.
        let grouped = Dictionary(grouping: outflows) { canonicalMerchant($0.merchant) }

        var results: [DetectedSubscription] = []
        for (canonical, raw) in grouped {
            guard !ignored.contains(canonical) else { continue }
            guard raw.count >= minOccurrences else { continue }
            let sorted = raw.sorted { $0.date < $1.date }
            guard let detected = match(sortedTransactions: sorted, canonical: canonical, now: now) else { continue }
            results.append(detected)
        }
        return results.sorted { $0.totalSpend > $1.totalSpend }
    }

    /// Manage the user's list of ignored merchants.
    static func ignore(_ merchant: String) {
        var ignored = (UserDefaults.standard.array(forKey: ignoredMerchantsKey) as? [String]) ?? []
        let canonical = canonicalMerchant(merchant)
        if !ignored.contains(canonical) {
            ignored.append(canonical)
            UserDefaults.standard.set(ignored, forKey: ignoredMerchantsKey)
        }
    }

    static func restore(_ merchant: String) {
        let ignored = (UserDefaults.standard.array(forKey: ignoredMerchantsKey) as? [String]) ?? []
        let canonical = canonicalMerchant(merchant)
        let filtered = ignored.filter { $0 != canonical }
        UserDefaults.standard.set(filtered, forKey: ignoredMerchantsKey)
    }

    static var ignoredMerchants: [String] {
        (UserDefaults.standard.array(forKey: ignoredMerchantsKey) as? [String]) ?? []
    }

    // MARK: Internals

    private static func match(
        sortedTransactions: [TransactionModel],
        canonical: String,
        now: Date
    ) -> DetectedSubscription? {
        let cal = Calendar.current

        // Intervals in days between consecutive charges.
        var intervals: [Int] = []
        for i in 1..<sortedTransactions.count {
            let days = cal.dateComponents([.day], from: sortedTransactions[i - 1].date, to: sortedTransactions[i].date).day ?? 0
            if days > 0 { intervals.append(days) }
        }
        guard !intervals.isEmpty else { return nil }
        let medianInterval = median(intervals.map(Double.init))

        // Match median to nearest known cadence within tolerance.
        guard let cadence = SubscriptionCadence.allCases.first(where: {
            abs(Double($0.intervalDays) - medianInterval) <= Double($0.matchTolerance)
        }) else { return nil }

        // Amount stability: all occurrences must be within ±15% of the median absolute amount.
        let absAmounts = sortedTransactions.map { absDecimal($0.amount) }
        let medianAmount = medianDecimal(absAmounts)
        guard medianAmount > 0 else { return nil }
        let withinSpread = absAmounts.allSatisfy { amount in
            let diff = absDecimal(amount - medianAmount)
            let spread = NSDecimalNumber(decimal: diff).doubleValue / NSDecimalNumber(decimal: medianAmount).doubleValue
            return spread <= 0.15
        }
        guard withinSpread else { return nil }

        guard let last = sortedTransactions.last else { return nil }
        let predictedNext = cal.date(byAdding: .day, value: cadence.intervalDays, to: last.date) ?? last.date

        // Stale guard: if we haven't seen a charge in 2x the cadence, skip —
        // user probably cancelled.
        let staleCutoff = cal.date(byAdding: .day, value: cadence.intervalDays * 2, to: last.date) ?? last.date
        guard staleCutoff > now else { return nil }

        let total = absAmounts.reduce(Decimal.zero, +)
        let displayMerchant = mostCommonDisplayName(sortedTransactions.map(\.merchant)) ?? canonical

        return DetectedSubscription(
            id: UUID(),
            merchant: displayMerchant,
            typicalAmount: medianAmount,
            cadence: cadence,
            occurrences: sortedTransactions.reversed(),
            lastChargeDate: last.date,
            predictedNextDate: predictedNext,
            totalSpend: total
        )
    }

    static func canonicalMerchant(_ merchant: String) -> String {
        merchant
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private static func mostCommonDisplayName(_ names: [String]) -> String? {
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        if sorted.isEmpty { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func medianDecimal(_ values: [Decimal]) -> Decimal {
        let sorted = values.sorted()
        if sorted.isEmpty { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func absDecimal(_ d: Decimal) -> Decimal {
        d < 0 ? -d : d
    }
}

// MARK: - View

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [TransactionModel]
    @Query private var scheduled: [ScheduledItemModel]

    @State private var entitlements = Entitlements.shared
    @State private var showingPaywall = false
    @State private var detected: [DetectedSubscription] = []
    @State private var addedNotice: String?
    @State private var showingIgnored = false

    var body: some View {
        NavigationStack {
            Group {
                if !entitlements.canUseSubscriptionTracker {
                    LockedFeatureCard(feature: .subscriptionTracker) {
                        showingPaywall = true
                    }
                    .frame(maxHeight: .infinity)
                    .summitListBackground()
                } else {
                    listContent
                }
            }
            .navigationTitle("Subscriptions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if entitlements.canUseSubscriptionTracker {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Re-scan") { rescan() }
                            Button("Show Ignored…") { showingIgnored = true }
                                .disabled(SubscriptionDetector.ignoredMerchants.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $showingIgnored) { IgnoredMerchantsView(onChange: rescan) }
            .onAppear { rescan() }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if detected.isEmpty {
            ContentUnavailableView {
                Label("No Subscriptions Detected", systemImage: "repeat.circle")
            } description: {
                Text("Once you've had a few months of transactions, Summit will surface every recurring charge here.")
            }
        } else {
            List {
                if let notice = addedNotice {
                    Section {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    }
                }

                Section {
                    HStack {
                        Text("\(detected.count) detected")
                        Spacer()
                        Text("\(currencyString(monthlyEstimate))/mo est.")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                Section("Detected") {
                    ForEach(detected) { sub in
                        SubscriptionRow(
                            sub: sub,
                            alreadyScheduled: isAlreadyScheduled(sub),
                            onSchedule: { schedule(sub) },
                            onIgnore: { ignore(sub) }
                        )
                    }
                }
                .summitRowBackground()
            }
            .summitListBackground()
        }
    }

    // MARK: Actions

    private var monthlyEstimate: Decimal {
        detected.reduce(Decimal.zero) { acc, sub in
            let perMonth: Decimal
            switch sub.cadence {
            case .weekly: perMonth = sub.typicalAmount * 4
            case .biweekly: perMonth = sub.typicalAmount * 2
            case .monthly: perMonth = sub.typicalAmount
            case .quarterly: perMonth = sub.typicalAmount / 3
            case .yearly: perMonth = sub.typicalAmount / 12
            }
            return acc + perMonth
        }
    }

    private func rescan() {
        detected = SubscriptionDetector.detect(transactions: transactions)
        addedNotice = nil
    }

    private func isAlreadyScheduled(_ sub: DetectedSubscription) -> Bool {
        let canonical = SubscriptionDetector.canonicalMerchant(sub.merchant)
        return scheduled.contains { item in
            SubscriptionDetector.canonicalMerchant(item.name) == canonical
        }
    }

    private func schedule(_ sub: DetectedSubscription) {
        let item = ScheduledItemModel(
            kind: .subscription,
            name: sub.merchant,
            amount: -sub.typicalAmount,
            nextDate: sub.predictedNextDate,
            intervalDays: sub.cadence.intervalDays,
            account: sub.occurrences.first?.account,
            category: sub.occurrences.first?.category
        )
        context.insert(item)
        try? context.save()
        addedNotice = "Added \(sub.merchant) to Horizon."
    }

    private func ignore(_ sub: DetectedSubscription) {
        SubscriptionDetector.ignore(sub.merchant)
        rescan()
    }

    private func currencyString(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "$0"
    }
}

private struct SubscriptionRow: View {
    let sub: DetectedSubscription
    let alreadyScheduled: Bool
    let onSchedule: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.merchant)
                        .font(.body.weight(.medium))
                    Text("\(sub.cadence.displayName) · \(sub.occurrenceCount) charges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(currencyString(sub.typicalAmount))
                        .monospacedDigit()
                    Text(totalLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                Label("Next \(sub.predictedNextDate.formatted(date: .abbreviated, time: .omitted))",
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if alreadyScheduled {
                    Label("Already scheduled", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onIgnore) {
                Label("Ignore", systemImage: "eye.slash")
            }
            if !alreadyScheduled {
                Button(action: onSchedule) {
                    Label("Add", systemImage: "plus")
                }
                .tint(.blue)
            }
        }
    }

    private var totalLabel: String {
        "\(currencyString(sub.totalSpend)) total"
    }

    private func currencyString(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "$0"
    }
}

private struct IgnoredMerchantsView: View {
    @Environment(\.dismiss) private var dismiss
    var onChange: () -> Void
    @State private var ignored: [String] = SubscriptionDetector.ignoredMerchants

    var body: some View {
        NavigationStack {
            List {
                if ignored.isEmpty {
                    Text("No ignored merchants.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ignored, id: \.self) { merchant in
                        HStack {
                            Text(merchant)
                            Spacer()
                            Button("Restore") {
                                SubscriptionDetector.restore(merchant)
                                ignored.removeAll(where: { $0 == merchant })
                                onChange()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Ignored")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
