import Foundation
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - Service

/// Schedules local notifications for budget threshold breaches and unusual
/// charges. All checks read configuration from UserDefaults and dedupe by
/// stable keys, so this is safe to invoke after every sync without spamming.
@Observable
@MainActor
final class SmartAlertsService {
    static let shared = SmartAlertsService()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    fileprivate static let budgetEnabledKey = "alerts.budget.enabled"
    fileprivate static let budgetThresholdKey = "alerts.budget.threshold"
    fileprivate static let unusualEnabledKey = "alerts.unusual.enabled"
    fileprivate static let unusualAmountKey = "alerts.unusual.amount"

    private(set) var isAuthorized: Bool = false
    private(set) var lastCheckSent: Int = 0

    var budgetAlertsEnabled: Bool {
        get { defaults.object(forKey: Self.budgetEnabledKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Self.budgetEnabledKey) }
    }

    /// 50, 80, 100 — the percent of assigned that triggers an alert.
    var budgetThresholdPercent: Int {
        get { defaults.object(forKey: Self.budgetThresholdKey) as? Int ?? 80 }
        set { defaults.set(newValue, forKey: Self.budgetThresholdKey) }
    }

    var unusualAlertsEnabled: Bool {
        get { defaults.object(forKey: Self.unusualEnabledKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Self.unusualEnabledKey) }
    }

    var unusualAmountThreshold: Decimal {
        get {
            if let s = defaults.string(forKey: Self.unusualAmountKey), let d = Decimal(string: s) { return d }
            return 200
        }
        set { defaults.set(NSDecimalNumber(decimal: newValue).stringValue, forKey: Self.unusualAmountKey) }
    }

    private init() {}

    // MARK: Permission

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
    }

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    // MARK: Checks

    /// Run all enabled checks for the supplied budget month. Safe to call
    /// from anywhere; gates itself on entitlement + auth + per-toggle config.
    @discardableResult
    func runChecks(context: ModelContext, year: Int, month: Int) async -> Int {
        guard Entitlements.shared.canUseSmartAlerts else { return 0 }
        await refreshAuthorization()
        guard isAuthorized else { return 0 }

        var sent = 0
        if budgetAlertsEnabled {
            sent += await runBudgetChecks(context: context, year: year, month: month)
        }
        if unusualAlertsEnabled {
            sent += await runUnusualChargeChecks(context: context)
        }
        lastCheckSent = sent
        return sent
    }

    // MARK: Budget thresholds

    private func runBudgetChecks(context: ModelContext, year: Int, month: Int) async -> Int {
        let monthDescriptor = FetchDescriptor<BudgetMonthModel>(predicate: #Predicate {
            $0.year == year && $0.month == month
        })
        guard let bm = (try? context.fetch(monthDescriptor))?.first else { return 0 }

        guard let categories = try? context.fetch(FetchDescriptor<CategoryModel>()) else { return 0 }

        let threshold = budgetThresholdPercent
        let thresholdDouble = Double(threshold)
        var sent = 0

        for category in categories {
            let assigned = BudgetEngine.assigned(for: category, in: bm)
            guard assigned > 0 else { continue }
            // `activity` is the signed sum: negative for outflows. We want
            // the magnitude of spending in the current month.
            let spent = -BudgetEngine.activity(for: category, year: year, month: month)
            guard spent > 0 else { continue }

            let pct = (NSDecimalNumber(decimal: spent).doubleValue
                       / NSDecimalNumber(decimal: assigned).doubleValue) * 100
            guard pct >= thresholdDouble else { continue }

            let dedupKey = "alert.budget.\(category.id.uuidString).\(year).\(month).\(threshold)"
            guard !defaults.bool(forKey: dedupKey) else { continue }

            let title = "\(category.name) budget"
            let body = "You've spent \(currencyString(spent)) of \(currencyString(assigned)) — \(Int(pct.rounded()))%."
            await scheduleNotification(title: title, body: body, identifier: dedupKey)
            defaults.set(true, forKey: dedupKey)
            sent += 1
        }
        return sent
    }

    // MARK: Unusual charges

    private func runUnusualChargeChecks(context: ModelContext) async -> Int {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let descriptor = FetchDescriptor<TransactionModel>(predicate: #Predicate {
            $0.date >= cutoff && $0.amount < 0
        })
        guard let recent = try? context.fetch(descriptor) else { return 0 }

        let threshold = unusualAmountThreshold
        var sent = 0
        for tx in recent {
            let absAmount = -tx.amount
            guard absAmount >= threshold else { continue }

            let dedupKey = "alert.tx.\(tx.id.uuidString)"
            guard !defaults.bool(forKey: dedupKey) else { continue }

            // Is this merchant new? Count any earlier transaction with the
            // same merchant string.
            let merchant = tx.merchant
            let date = tx.date
            let priorDescriptor = FetchDescriptor<TransactionModel>(predicate: #Predicate {
                $0.merchant == merchant && $0.date < date
            })
            let priorCount = (try? context.fetchCount(priorDescriptor)) ?? 0
            let isNewMerchant = priorCount == 0

            let title = isNewMerchant ? "New-merchant charge" : "Unusual charge"
            let suffix = isNewMerchant ? " — first time at this merchant." : "."
            let body = "\(tx.merchant): \(currencyString(absAmount))\(suffix)"
            await scheduleNotification(title: title, body: body, identifier: dedupKey)
            defaults.set(true, forKey: dedupKey)
            sent += 1
        }
        return sent
    }

    // MARK: Test + helpers

    func scheduleTestNotification() async {
        await scheduleNotification(
            title: "Summit Alerts",
            body: "This is what a Summit alert looks like.",
            identifier: "alert.test.\(UUID().uuidString)"
        )
    }

    private func scheduleNotification(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func currencyString(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "$0"
    }
}

// MARK: - View

struct SmartAlertsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entitlements = Entitlements.shared
    @State private var service = SmartAlertsService.shared
    @State private var showingPaywall = false
    @State private var testStatus: String?

    var body: some View {
        NavigationStack {
            Group {
                if !entitlements.canUseSmartAlerts {
                    LockedFeatureCard(feature: .smartAlerts) {
                        showingPaywall = true
                    }
                    .frame(maxHeight: .infinity)
                    .summitListBackground()
                } else {
                    formContent
                }
            }
            .navigationTitle("Smart Alerts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .task { await service.refreshAuthorization() }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            permissionSection
            budgetSection
            unusualSection
            testSection
        }
        .summitListBackground()
    }

    private var permissionSection: some View {
        Section("Permission") {
            HStack(spacing: 12) {
                Image(systemName: service.isAuthorized ? "bell.badge.fill" : "bell.slash")
                    .foregroundStyle(service.isAuthorized ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.isAuthorized ? "Notifications enabled" : "Notifications disabled")
                    if !service.isAuthorized {
                        Text("Tap below to allow Summit to send alerts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !service.isAuthorized {
                Button("Enable Notifications") {
                    Task { _ = await service.requestPermission() }
                }
                .accessibilityIdentifier("enableNotificationsButton")
            }
        }
    }

    private var budgetSection: some View {
        Section {
            Toggle("Alert near category limit", isOn: Binding(
                get: { service.budgetAlertsEnabled },
                set: { service.budgetAlertsEnabled = $0 }
            ))
            .accessibilityIdentifier("budgetAlertsToggle")

            if service.budgetAlertsEnabled {
                Picker("Threshold", selection: Binding(
                    get: { service.budgetThresholdPercent },
                    set: { service.budgetThresholdPercent = $0 }
                )) {
                    Text("50%").tag(50)
                    Text("80%").tag(80)
                    Text("100%").tag(100)
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Budget Thresholds")
        } footer: {
            Text("You'll get one notification per category each month when spending crosses your chosen percentage of assigned.")
        }
    }

    private var unusualSection: some View {
        Section {
            Toggle("Alert on large or new-merchant charges", isOn: Binding(
                get: { service.unusualAlertsEnabled },
                set: { service.unusualAlertsEnabled = $0 }
            ))
            .accessibilityIdentifier("unusualAlertsToggle")

            if service.unusualAlertsEnabled {
                HStack {
                    Text("Threshold")
                    Spacer()
                    TextField("Amount", value: Binding(
                        get: { service.unusualAmountThreshold },
                        set: { service.unusualAmountThreshold = $0 }
                    ), format: .currency(code: "USD"))
                    .multilineTextAlignment(.trailing)
                    #if canImport(UIKit)
                    .keyboardType(.decimalPad)
                    #endif
                }
            }
        } header: {
            Text("Unusual Charges")
        } footer: {
            Text("Get notified when an outflow exceeds the threshold, with an extra flag if it's from a merchant you've never seen before.")
        }
    }

    private var testSection: some View {
        Section {
            Button("Send Test Notification") {
                Task {
                    await service.scheduleTestNotification()
                    testStatus = "Test notification queued."
                }
            }
            .disabled(!service.isAuthorized)
            .accessibilityIdentifier("sendTestNotificationButton")

            if let status = testStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Alerts run automatically after each sync. Use this to confirm the system is wired up correctly.")
        }
    }
}
