import SwiftUI
import SwiftData

enum TabKind: String, CaseIterable, Identifiable {
    case budget, transactions, netWorth, horizon, reports, insights, settings

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .budget: "Budget"
        case .transactions: "Transactions"
        case .netWorth: "Net Worth"
        case .horizon: "Horizon"
        case .reports: "Reports"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    var defaultIcon: String {
        switch self {
        case .budget: "list.bullet.rectangle"
        case .transactions: "creditcard"
        case .netWorth: "chart.line.uptrend.xyaxis"
        case .horizon: "mountain.2"
        case .reports: "chart.pie"
        case .insights: "sparkles"
        case .settings: "gearshape"
        }
    }

    var titleKey: String { "\(rawValue)Title" }
    var iconKey: String { "\(rawValue)Icon" }
}

let defaultTabOrder = TabKind.allCases.map(\.rawValue).joined(separator: ",")

extension Notification.Name {
    /// Posted by the menu-bar "New Transaction" command (⌘N); RootView presents the editor.
    static let summitQuickAdd = Notification.Name("summit.quickAdd")
}

struct RootView: View {
    @AppStorage("tabOrder") private var tabOrderRaw: String = defaultTabOrder
    @AppStorage("appAccentHex") private var appAccentHex: String = ""
    @AppStorage("appBackgroundHex") private var appBackgroundHex: String = ""

    @State private var selectedTab: TabKind = .budget
    @State private var showingQuickAdd = false
    @State private var showingReviewInbox = false
    @State private var showingWeeklyReview = false
    @State private var showingMonthRecap = false
    @State private var showingWelcome = false
    @State private var showingWelcomeConnections = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    private var appLock = AppLockService.shared

    private var orderedTabs: [TabKind] {
        let saved = tabOrderRaw.split(separator: ",").compactMap { TabKind(rawValue: String($0)) }
        let missing = TabKind.allCases.filter { !saved.contains($0) }
        return saved + missing
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(orderedTabs) { tab in
                Tab(value: tab) {
                    tabContent(for: tab)
                } label: {
                    TabLabel(kind: tab)
                }
            }
        }
        // Tab bar on iPhone; sidebar on iPad and the Mac (Designed for iPad).
        .tabViewStyle(.sidebarAdaptable)
        .tint(Color(hex: appAccentHex) ?? .accentColor)
        .monospacedDigit()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SummitSyncHUD()
        }
        .sheet(isPresented: $showingQuickAdd) {
            TransactionEditor(editing: nil)
        }
        .onOpenURL { url in
            // summit://add — from the Control Center control or Quick Add widget.
            if url.scheme == "summit", url.host == "add" {
                showingQuickAdd = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .summitQuickAdd)) { _ in
            // ⌘N from the menu bar (Mac / iPad hardware keyboard).
            showingQuickAdd = true
        }
        // Engagement-nudge notification taps, routed via NudgeRoutingDelegate.
        .onReceive(NotificationCenter.default.publisher(for: .summitOpenReviewInbox)) { _ in
            showingReviewInbox = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .summitOpenWeeklyReview)) { _ in
            showingWeeklyReview = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .summitOpenMonthRecap)) { _ in
            showingMonthRecap = true
        }
        .sheet(isPresented: $showingReviewInbox) {
            ReviewInboxView()
        }
        .sheet(isPresented: $showingWeeklyReview) {
            WeeklyReviewView()
        }
        .sheet(isPresented: $showingMonthRecap) {
            MonthRecapView()
        }
        // Getting Started rows on other tabs route here; RootView owns the selection.
        .onReceive(NotificationCenter.default.publisher(for: .summitSelectTab)) { note in
            if let raw = note.object as? String, let kind = TabKind(rawValue: raw) {
                selectedTab = kind
            }
        }
        .onAppear {
            OnboardingState.skipForExistingUser(context: modelContext)
            showingWelcome = !OnboardingState.hasCompletedWelcome
        }
        .fullScreenCover(isPresented: $showingWelcome) {
            OnboardingWelcomeView(
                onFinish: {
                    OnboardingState.hasCompletedWelcome = true
                    showingWelcome = false
                },
                onConnectBank: {
                    OnboardingState.hasCompletedWelcome = true
                    showingWelcome = false
                    showingWelcomeConnections = true
                }
            )
        }
        .sheet(isPresented: $showingWelcomeConnections) {
            NavigationStack {
                PlaidConnectionsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingWelcomeConnections = false }
                        }
                    }
            }
        }
        .overlay {
            if appLock.isLocked {
                AppLockScreen()
            } else if appLock.isEnabled && scenePhase != .active {
                // Keeps balances out of the app-switcher snapshot.
                AppPrivacyShield()
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: TabKind) -> some View {
        Group {
            switch tab {
            case .budget: BudgetView()
            case .transactions: TransactionsView()
            case .netWorth: NetWorthView()
            case .horizon: HorizonView()
            case .reports: ReportsView()
            case .insights: AIInsightsView()
            case .settings: SettingsView()
            }
        }
        .transition(.opacity)
        .id(tab)
        .animation(.smooth(duration: 0.22), value: selectedTab)
    }
}

private struct TabLabel: View {
    let kind: TabKind
    @AppStorage private var title: String
    @AppStorage private var icon: String

    init(kind: TabKind) {
        self.kind = kind
        self._title = AppStorage(wrappedValue: kind.defaultTitle, kind.titleKey)
        self._icon = AppStorage(wrappedValue: kind.defaultIcon, kind.iconKey)
    }

    var body: some View {
        Label(title, systemImage: icon)
    }
}

@Observable
@MainActor
final class AppSyncStatus {
    static let shared = AppSyncStatus()
    private init() {}

    private(set) var activePlaidSyncs: Int = 0
    private(set) var lastError: String?

    var isPlaidSyncing: Bool { activePlaidSyncs > 0 }

    func beginPlaidSync() { activePlaidSyncs += 1 }

    func endPlaidSync(error: Error? = nil) {
        activePlaidSyncs = max(0, activePlaidSyncs - 1)
        if let error { lastError = error.localizedDescription }
    }

    func clearError() { lastError = nil }
}

struct SummitSyncHUD: View {
    private let syncService = SyncService.shared
    private let appSync = AppSyncStatus.shared

    var body: some View {
        let isSyncing = syncService.isSyncing || appSync.isPlaidSyncing
        ZStack {
            if isSyncing {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(height: 2)
                    .transition(.opacity)
                    .accessibilityLabel("Syncing")
                    .accessibilityIdentifier("syncHUD")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isSyncing ? 2 : 0)
        .animation(.smooth(duration: 0.2), value: isSyncing)
    }
}

/// Applies the user's chosen background color to a scrollable container (Form/List/ScrollView).
/// Must be attached directly to the scrollable view, not its parent — `scrollContentBackground` doesn't cascade through `NavigationStack`.
struct SummitListBackground: ViewModifier {
    @AppStorage("appBackgroundHex") private var appBackgroundHex: String = ""

    func body(content: Content) -> some View {
        if let color = Color(hex: appBackgroundHex) {
            content
                .scrollContentBackground(.hidden)
                .background(color.ignoresSafeArea())
        } else {
            content
        }
    }
}

extension View {
    /// Apply on each tab's Form/List/ScrollView so the user's background color shows through.
    func summitListBackground() -> some View { modifier(SummitListBackground()) }

    /// Apply to each `Section` so its rows pick up the user's row background color.
    func summitRowBackground() -> some View { modifier(SummitRowBackground()) }

    /// Apply to each tab's root container (inside its NavigationStack) so
    /// content stays a readable width on iPad/Mac instead of stretching
    /// edge-to-edge. No-op in compact width (iPhone portrait).
    func summitReadableWidth() -> some View { modifier(SummitReadableWidth()) }
}

/// Caps content width on wide layouts and fills the side gutters with the
/// list background color so the cap reads as margins, not a cropped view.
struct SummitReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    @AppStorage("appBackgroundHex") private var appBackgroundHex: String = ""

    func body(content: Content) -> some View {
        if hSize == .regular {
            content
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .background((Color(hex: appBackgroundHex) ?? Color(.systemGroupedBackground)).ignoresSafeArea())
        } else {
            content
        }
    }
}

/// Reads the user's chosen row background color from AppStorage and applies `.listRowBackground`.
/// Falls back to the system default when the user hasn't picked a color.
struct SummitRowBackground: ViewModifier {
    @AppStorage("appRowBgHex") private var appRowBgHex: String = ""

    func body(content: Content) -> some View {
        if let color = Color(hex: appRowBgHex) {
            content.listRowBackground(color)
        } else {
            content
        }
    }
}

extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let R = Int(round(r * 255)), G = Int(round(g * 255)), B = Int(round(b * 255))
        return String(format: "%02X%02X%02X", R, G, B)
        #else
        return nil
        #endif
    }
}
