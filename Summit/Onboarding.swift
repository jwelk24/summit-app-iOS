import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Onboarding state

/// First-run helper state. Everything here is device-local by design:
/// onboarding is about *this* device's first launch, so none of it syncs.
enum OnboardingState {
    static let welcomeDoneKey = "onboarding.welcomeDone"
    static let checklistDismissedKey = "onboarding.checklistDismissed"
    static let accountsVisitedKey = "onboarding.accountsVisited"
    static let tourDoneKey = "onboarding.tourDone"

    static var hasCompletedWelcome: Bool {
        get { UserDefaults.standard.bool(forKey: welcomeDoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: welcomeDoneKey) }
    }

    static var isChecklistDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: checklistDismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: checklistDismissedKey) }
    }

    static var hasVisitedAccounts: Bool {
        get { UserDefaults.standard.bool(forKey: accountsVisitedKey) }
        set { UserDefaults.standard.set(newValue, forKey: accountsVisitedKey) }
    }

    /// Completing the guided feature tour (closing it early doesn't count,
    /// so the checklist step stays available to retake).
    static var hasTakenTour: Bool {
        get { UserDefaults.standard.bool(forKey: tourDoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: tourDoneKey) }
    }

    /// UI-test hook: launching with `--uitest-reset-onboarding` forces the
    /// welcome flow regardless of existing data (see RootView.onAppear).
    static var isUITestReset: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-reset-onboarding")
    }

    static func resetForUITests() {
        hasCompletedWelcome = false
        isChecklistDismissed = false
        hasVisitedAccounts = false
        hasTakenTour = false
    }

    /// Anyone with real data predates the welcome flow — mark it (and the
    /// checklist) done silently so an app update never greets an existing
    /// user like a new install. The seed creates exactly 3 sample
    /// transactions, so anything beyond that, a linked connection, or a
    /// signed-in session counts as real use.
    @MainActor
    static func skipForExistingUser(context: ModelContext) {
        guard !hasCompletedWelcome else { return }
        let txCount = (try? context.fetchCount(FetchDescriptor<TransactionModel>())) ?? 0
        let plaidLinks = (try? context.fetchCount(FetchDescriptor<PlaidAccountLinkModel>())) ?? 0
        let walletLinks = (try? context.fetchCount(FetchDescriptor<FinanceKitAccountLinkModel>())) ?? 0
        if txCount > 3 || plaidLinks > 0 || walletLinks > 0 || SupabaseService.shared.isAuthenticated {
            hasCompletedWelcome = true
            isChecklistDismissed = true
        }
    }
}

extension Notification.Name {
    /// Posted by onboarding steps whose destination lives on another tab;
    /// RootView switches. The notification object is the TabKind rawValue.
    static let summitSelectTab = Notification.Name("summit.selectTab")
}

// MARK: - Welcome flow

/// Three-page first-launch flow: what Summit is, what the starter budget is,
/// and how to bring money in. Presented once as a full-screen cover from
/// RootView; every exit path calls `onFinish`.
struct OnboardingWelcomeView: View {
    var onFinish: () -> Void
    /// "Connect a Bank" on the last page: RootView finishes the flow and
    /// opens the connections sheet.
    var onConnectBank: () -> Void

    @State private var page = 0
    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { onFinish() }
                    .foregroundStyle(.secondary)
                    .opacity(page < lastPage ? 1 : 0)
                    .disabled(page >= lastPage)
                    .accessibilityIdentifier("onboardingSkipButton")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            TabView(selection: $page) {
                welcomePage.tag(0)
                starterBudgetPage.tag(1)
                bringMoneyPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                if page == lastPage {
                    Button {
                        onConnectBank()
                    } label: {
                        Label("Connect a Bank", systemImage: "building.columns")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("onboardingConnectBankButton")
                }

                Button {
                    if page < lastPage {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < lastPage ? "Continue" : "Start Budgeting")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboardingContinueButton")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var welcomePage: some View {
        OnboardingPage(
            icon: "mountain.2.fill",
            title: "Welcome to Summit",
            subtitle: "Budget, net worth, and the road ahead — in one place."
        ) {
            OnboardingFeatureRow(
                icon: "list.bullet.rectangle",
                title: "Give every dollar a job",
                detail: "Assign your money to categories so you always know what's safe to spend."
            )
            OnboardingFeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Track your net worth",
                detail: "Accounts, investments, and debts in one picture that updates as you do."
            )
            OnboardingFeatureRow(
                icon: "calendar",
                title: "See what's coming",
                detail: "Upcoming bills, cash-flow forecasts, and goals on the Horizon tab."
            )
        }
    }

    private var starterBudgetPage: some View {
        OnboardingPage(
            icon: "list.bullet.rectangle.fill",
            title: "Your Starter Budget",
            subtitle: "We set up common categories and sample accounts so you can look around."
        ) {
            OnboardingFeatureRow(
                icon: "square.stack.3d.up",
                title: "The numbers are examples",
                detail: "The accounts, balances, and transactions you'll see are samples — swap in your real ones."
            )
            OnboardingFeatureRow(
                icon: "slider.horizontal.3",
                title: "Everything is editable",
                detail: "Rename categories, add your own, and delete anything you don't need."
            )
            OnboardingFeatureRow(
                icon: "checklist",
                title: "A checklist guides you",
                detail: "The Getting Started checklist on the Budget tab walks you through making it yours."
            )
        }
    }

    private var bringMoneyPage: some View {
        OnboardingPage(
            icon: "arrow.down.circle.fill",
            title: "Bring In Your Money",
            subtitle: "Connect accounts for automatic imports, or log things yourself."
        ) {
            OnboardingFeatureRow(
                icon: "building.columns",
                title: "Connect your bank",
                detail: "Transactions and balances import automatically."
            )
            OnboardingFeatureRow(
                icon: "wallet.pass",
                title: "Apple Card & Apple Cash",
                detail: "Import from Apple Wallet — that data never leaves your device."
            )
            OnboardingFeatureRow(
                icon: "plus.circle",
                title: "Or log it yourself",
                detail: "Quick-add transactions, scan receipts, or use widgets and Siri."
            )
            OnboardingFeatureRow(
                icon: "lock",
                title: "Private by default",
                detail: "Your data stays on this device unless you sign in to back up and sync."
            )
        }
    }
}

/// Shared layout for one welcome page: big icon, title, subtitle, feature rows.
private struct OnboardingPage<Rows: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let rows: Rows

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 20) {
                    rows
                }
                .padding(.top, 20)
                .frame(maxWidth: 480)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Getting Started checklist

/// Checklist section for the top of the Budget tab. Renders nothing once
/// dismissed or when every step is done. Steps track real completion where
/// the data can tell us (transaction logged, connection linked, notifications
/// granted, signed in); the accounts step completes when visited.
struct GettingStartedSection: View {
    /// Total transactions in the store — the seed creates 3, so more than
    /// that means the user has logged or imported their own.
    let transactionCount: Int

    @AppStorage(OnboardingState.checklistDismissedKey) private var dismissed = false
    @AppStorage(OnboardingState.accountsVisitedKey) private var accountsVisited = false
    @AppStorage(OnboardingState.tourDoneKey) private var tourDone = false

    @Query private var plaidLinks: [PlaidAccountLinkModel]
    @Query private var walletLinks: [FinanceKitAccountLinkModel]

    @State private var supabase = SupabaseService.shared
    @State private var alerts = SmartAlertsService.shared
    @State private var showingConnections = false
    @State private var showingSignIn = false

    @Environment(\.openURL) private var openURL

    private var hasLoggedTransaction: Bool { transactionCount > 3 }
    private var hasConnection: Bool { !plaidLinks.isEmpty || !walletLinks.isEmpty }

    private var doneStates: [Bool] {
        [tourDone, accountsVisited, hasLoggedTransaction, hasConnection, alerts.isAuthorized, supabase.isAuthenticated]
    }
    private var doneCount: Int { doneStates.count(where: { $0 }) }
    private var allDone: Bool { doneCount == doneStates.count }

    var body: some View {
        if !dismissed && !allDone {
            Section {
                header
                    .task { await alerts.refreshAuthorization() }

                ChecklistRow(
                    icon: "map",
                    title: "Take the tour",
                    subtitle: "A guided look at what lives on each tab.",
                    done: tourDone,
                    identifier: "gettingStartedTour"
                ) {
                    NotificationCenter.default.post(name: .summitStartTour, object: nil)
                }

                ChecklistRow(
                    icon: "building.columns",
                    title: "Set your real balances",
                    subtitle: "Replace the sample accounts on the Net Worth tab.",
                    done: accountsVisited,
                    identifier: "gettingStartedAccounts"
                ) {
                    accountsVisited = true
                    NotificationCenter.default.post(name: .summitSelectTab, object: TabKind.netWorth.rawValue)
                }

                ChecklistRow(
                    icon: "plus.circle",
                    title: "Log a transaction",
                    subtitle: "Add a purchase by hand to see your budget react.",
                    done: hasLoggedTransaction,
                    identifier: "gettingStartedTransaction"
                ) {
                    NotificationCenter.default.post(name: .summitQuickAdd, object: nil)
                }

                ChecklistRow(
                    icon: "link",
                    title: "Connect a bank or Apple Wallet",
                    subtitle: "Transactions import automatically once linked.",
                    done: hasConnection,
                    identifier: "gettingStartedConnect"
                ) {
                    showingConnections = true
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
                }

                ChecklistRow(
                    icon: "bell.badge",
                    title: "Turn on reminders",
                    subtitle: "Bill reminders and weekly check-ins, computed on device.",
                    done: alerts.isAuthorized,
                    identifier: "gettingStartedNotifications"
                ) {
                    enableNotifications()
                }

                ChecklistRow(
                    icon: "icloud",
                    title: "Back up & sync",
                    subtitle: "Sign in to protect your data and share with a partner.",
                    done: supabase.isAuthenticated,
                    identifier: "gettingStartedSignIn"
                ) {
                    showingSignIn = true
                }
                .sheet(isPresented: $showingSignIn) {
                    NavigationStack { AuthView() }
                }
            }
            .summitRowBackground()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Gauge(value: Double(doneCount), in: 0...Double(doneStates.count)) {
                EmptyView()
            } currentValueLabel: {
                Text("\(doneCount)")
                    .font(.caption2.bold())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.accentColor)
            .scaleEffect(0.62)
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Getting Started")
                    .font(.headline)
                Text("\(doneCount) of \(doneStates.count) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    dismissed = true
                } label: {
                    Label("Hide Checklist", systemImage: "eye.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Checklist options")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Getting Started, \(doneCount) of \(doneStates.count) steps done")
        .accessibilityIdentifier("gettingStartedHeader")
    }

    private func enableNotifications() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .denied {
                // The system prompt can only be shown once; hand off to Settings.
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } else {
                await SmartAlertsService.shared.requestPermission()
            }
        }
    }
}

private struct ChecklistRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let done: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : icon)
                    .font(.title3)
                    .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !done {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(done)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}

// MARK: - Previews

#Preview("Welcome") {
    OnboardingWelcomeView(onFinish: {}, onConnectBank: {})
}

#Preview("Checklist") {
    List {
        GettingStartedSection(transactionCount: 3)
    }
    .modelContainer(try! ModelContainer(
        for: SummitSharedStore.schema,
        configurations: [ModelConfiguration(schema: SummitSharedStore.schema, isStoredInMemoryOnly: true)]
    ))
}
