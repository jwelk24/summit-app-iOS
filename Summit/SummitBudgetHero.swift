import SwiftUI

/// The Budget tab's hero in Summit's signature look: greeting, the night
/// mountain, the big "available this month" serif number, the budget-used
/// gradient bar, a four-tile category grid, and a Summit Insight card.
/// Pure presentation — BudgetView computes and passes everything in.
struct SummitBudgetHero: View {
    struct CategoryTile: Identifiable {
        let id: UUID
        let name: String
        let spent: Decimal
        let budget: Decimal
        let index: Int
    }

    let title: String
    let assigned: Decimal
    let spent: Decimal
    /// Unassigned money ("left to assign"), the old hero card's headline.
    let availableToBudget: Decimal
    /// 0...1 — fraction of income kept this month; drives the snow cap.
    let savingsRate: Double
    /// 0...1 — long-term wealth trajectory; drives the peak height.
    let netWorthTrend: Double
    let tiles: [CategoryTile]
    let insight: String

    private var remaining: Decimal { max(assigned - spent, 0) }
    private var usedFraction: Double {
        guard assigned > 0 else { return 0 }
        return (NSDecimalNumber(decimal: spent).doubleValue / NSDecimalNumber(decimal: assigned).doubleValue)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<12: "Good morning"
        case ..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting.uppercased())
                    .font(.caption.weight(.medium))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(.title, design: .serif, weight: .bold))
            }
            .padding(.horizontal, 24)

            SummitMountainView(
                savingsRate: savingsRate,
                budgetUsed: usedFraction,
                netWorthTrend: netWorthTrend
            )
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("Available this month".uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(currencySymbol)
                        .font(.system(size: 28, design: .serif).weight(.bold))
                        .foregroundStyle(SummitTheme.teal)
                    Text(wholeNumber(remaining))
                        .font(.system(size: 52, design: .serif).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text("of \(currencyWhole(assigned)) budget · \(Text("\(currencyWhole(spent)) spent").foregroundStyle(SummitTheme.amber).bold())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)

            VStack(spacing: 10) {
                HStack {
                    Text("Budget used")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(usedFraction.formatted(.percent.precision(.fractionLength(0))))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.footnote)
                SummitGradientBar(fraction: usedFraction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Budget used \(usedFraction.formatted(.percent.precision(.fractionLength(0))))")

            if availableToBudget != 0 {
                HStack(spacing: 8) {
                    Image(systemName: availableToBudget > 0 ? "tray.and.arrow.down" : "exclamationmark.triangle")
                    Text(availableToBudget > 0
                         ? "\(currencyWhole(availableToBudget)) left to assign"
                         : "\(currencyWhole(-availableToBudget)) over-assigned")
                        .fontWeight(.medium)
                }
                .font(.footnote)
                .foregroundStyle(availableToBudget > 0 ? SummitTheme.teal : SummitTheme.rose)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }

            if !tiles.isEmpty {
                Text("This Month")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 12)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(tiles) { tile in
                        SummitCategoryTile(tile: tile)
                    }
                }
                .padding(.horizontal, 24)
            }

            SummitInsightCard(text: insight)
                .padding(.horizontal, 24)
                .padding(.top, 18)
        }
        .padding(.vertical, 8)
    }

    private var currencySymbol: String {
        Locale.current.currencySymbol ?? "$"
    }
}

/// One card of the two-column category grid: emoji, tracked-caps name,
/// serif amount, and a mini progress bar in the card's cycle accent.
private struct SummitCategoryTile: View {
    let tile: SummitBudgetHero.CategoryTile

    private var accent: Color { SummitTheme.accent(at: tile.index) }
    private var fraction: Double {
        guard tile.budget > 0 else { return 0 }
        return NSDecimalNumber(decimal: tile.spent).doubleValue / NSDecimalNumber(decimal: tile.budget).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summitCategoryEmoji(tile.name))
                .font(.title3)
                .padding(.bottom, 7)
            Text(tile.name.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(currencyWhole(tile.spent))
                .font(.system(.title3, design: .serif, weight: .bold))
                .monospacedDigit()
            Text("of \(currencyWhole(tile.budget))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            SummitGradientBar(fraction: fraction, height: 3, tint: accent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SummitTheme.slate2, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .bottom) {
            UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20)
                .fill(accent)
                .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.name), spent \(currencyWhole(tile.spent)) of \(currencyWhole(tile.budget))")
    }
}

/// The "Summit Insight" teaser card; taps through to the Insights tab.
private struct SummitInsightCard: View {
    let text: String

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .summitSelectTab, object: TabKind.insights.rawValue)
        } label: {
            HStack(spacing: 14) {
                Text("⛰️")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(SummitTheme.teal.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Summit Insight".uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(SummitTheme.teal)
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.primary.opacity(0.75))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [SummitTheme.teal.opacity(0.12), SummitTheme.lavender.opacity(0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(SummitTheme.teal.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("summitInsightCard")
    }
}

// MARK: - Formatting

private func currencyWhole(_ d: Decimal) -> String {
    d.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")
        .precision(.fractionLength(0)))
}

private func wholeNumber(_ d: Decimal) -> String {
    d.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
}

// MARK: - Previews

#Preview("Budget hero") {
    ScrollView {
        SummitBudgetHero(
            title: "Budget",
            assigned: 5800,
            spent: 2560,
            availableToBudget: 240,
            savingsRate: 0.65,
            netWorthTrend: 0.75,
            tiles: [
                .init(id: UUID(), name: "Housing", spent: 1200, budget: 1800, index: 0),
                .init(id: UUID(), name: "Groceries", spent: 380, budget: 600, index: 1),
                .init(id: UUID(), name: "Dining", spent: 264, budget: 300, index: 2),
                .init(id: UUID(), name: "Travel", spent: 150, budget: 500, index: 3),
            ],
            insight: "You're on pace to save $480 extra this month."
        )
    }
    .background(SummitTheme.slate)
    .preferredColorScheme(.dark)
}
