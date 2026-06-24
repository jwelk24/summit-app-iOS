import SwiftUI

enum TabKind: String, CaseIterable, Identifiable {
    case budget, transactions, netWorth, horizon, reports, insights

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .budget: "Budget"
        case .transactions: "Transactions"
        case .netWorth: "Net Worth"
        case .horizon: "Horizon"
        case .reports: "Reports"
        case .insights: "Insights"
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
        }
    }

    var titleKey: String { "\(rawValue)Title" }
    var iconKey: String { "\(rawValue)Icon" }
}

let defaultTabOrder = TabKind.allCases.map(\.rawValue).joined(separator: ",")

struct RootView: View {
    @AppStorage("tabOrder") private var tabOrderRaw: String = defaultTabOrder
    @AppStorage("appAccentHex") private var appAccentHex: String = ""
    @AppStorage("appBackgroundHex") private var appBackgroundHex: String = ""

    private var orderedTabs: [TabKind] {
        let saved = tabOrderRaw.split(separator: ",").compactMap { TabKind(rawValue: String($0)) }
        let missing = TabKind.allCases.filter { !saved.contains($0) }
        return saved + missing
    }

    var body: some View {
        TabView {
            ForEach(orderedTabs) { tab in
                tabContent(for: tab)
                    .tabItem { TabLabel(kind: tab) }
            }
        }
        .tint(Color(hex: appAccentHex) ?? .accentColor)
    }

    @ViewBuilder
    private func tabContent(for tab: TabKind) -> some View {
        switch tab {
        case .budget: BudgetView()
        case .transactions: TransactionsView()
        case .netWorth: NetWorthView()
        case .horizon: HorizonView()
        case .reports: ReportsView()
        case .insights: AIInsightsView()
        }
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
