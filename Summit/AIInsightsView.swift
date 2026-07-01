import SwiftUI
import SwiftData
import FoundationModels

/// The "Insights" tab. Shows an AI-generated weekly digest and offers
/// one-tap smart categorization for transactions that have no category yet.
struct AIInsightsView: View {
    @Environment(\.modelContext) private var context

    @State private var availability: SystemLanguageModel.Availability = SystemLanguageModel.default.availability

    @State private var digest: AIInsightsService.WeeklyDigest?
    @State private var isGeneratingDigest = false

    @State private var isCategorizing = false
    @State private var categorizeProgress: (current: Int, total: Int)?
    @State private var categorizeResult: String?

    @State private var errorMessage: String?

    @State private var entitlements = Entitlements.shared
    @State private var showingPaywall = false

    @State private var question = ""
    @State private var answer: AIInsightsService.MoneyAnswer?
    @State private var isAsking = false

    @State private var coachInsights: [CoachInsight] = []

    var body: some View {
        NavigationStack {
            Group {
                if entitlements.canUseAIInsights {
                    VStack(spacing: 12) {
                        InsightsHeroCard(availability: availability, digestHeadline: digest?.headline)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        List {
                            coachSection
                            switch availability {
                            case .available:
                                askSection
                                digestSection
                                smartCategorizeSection
                                aboutSection
                            case .unavailable(let reason):
                                unavailableSection(reason)
                            }
                        }
                        .summitListBackground()
                    }
                } else {
                    LockedFeatureCard(feature: .aiInsights) {
                        showingPaywall = true
                    }
                    .frame(maxHeight: .infinity)
                    .summitListBackground()
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .task { loadCoach() }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .alert("AI Error", isPresented: errorBinding, presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    // MARK: Sections

    private var coachSection: some View {
        Section {
            if coachInsights.isEmpty {
                Label("You're on track — nothing notable right now.", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coachInsights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.icon)
                            .foregroundStyle(coachColor(insight.sentiment))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title).font(.subheadline.weight(.medium))
                            Text(insight.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            SummitSectionHeader(title: "Your Money Coach", systemImage: "figure.mind.and.body")
        } footer: {
            Text("Proactive insights, computed privately on your device.")
        }
        .summitRowBackground()
    }

    private func coachColor(_ sentiment: CoachInsight.Sentiment) -> Color {
        switch sentiment {
        case .positive: return .green
        case .negative: return .red
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }

    private func loadCoach() {
        coachInsights = FinancialCoach.insights(
            context: context,
            cushion: SmartAlertsService.shared.lowBalanceThreshold
        )
    }

    private var askSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(.tint)
                TextField("Ask about your money…", text: $question)
                    .submitLabel(.search)
                    .onSubmit { Task { await ask() } }
                    .accessibilityIdentifier("askMoneyField")
                if !question.isEmpty {
                    Button {
                        Task { await ask() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .disabled(isAsking)
                }
            }

            if isAsking {
                HStack {
                    ProgressView()
                    Text("Thinking…").foregroundStyle(.secondary)
                }
            } else if let answer {
                VStack(alignment: .leading, spacing: 10) {
                    Text(answer.text)
                        .font(.subheadline)
                    if !answer.matched.isEmpty {
                        Divider()
                        ForEach(Array(answer.matched.prefix(4))) { tx in
                            HStack {
                                Text(tx.merchant)
                                    .lineLimit(1)
                                Spacer()
                                Text(tx.amount.formatted(.currency(code: tx.account?.currencyCode ?? "USD")))
                                    .monospacedDigit()
                                    .foregroundStyle(tx.amount < 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.green))
                            }
                            .font(.caption)
                        }
                        if answer.matched.count > 4 {
                            Text("+ \(answer.matched.count - 4) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    exampleButton("How much did I spend on coffee last month?")
                    exampleButton("What did I spend this month?")
                    exampleButton("How much did I make this year?")
                }
            }
        } header: {
            SummitSectionHeader(title: "Ask Your Money", systemImage: "sparkle.magnifyingglass")
        } footer: {
            Text("Answered on-device from your own data — never sent to a server.")
        }
        .summitRowBackground()
    }

    private func exampleButton(_ text: String) -> some View {
        Button {
            question = text
            Task { await ask() }
        } label: {
            Label(text, systemImage: "text.bubble")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private var digestSection: some View {
        Section {
            if isGeneratingDigest {
                HStack {
                    ProgressView()
                    Text("Summarizing your week…")
                        .foregroundStyle(.secondary)
                }
            } else if let digest {
                VStack(alignment: .leading, spacing: 10) {
                    Text(digest.headline)
                        .font(.headline)
                    ForEach(Array(digest.bullets.enumerated()), id: \.offset) { _, bullet in
                        Label(bullet, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                            .font(.subheadline)
                    }
                    if !digest.suggestion.isEmpty {
                        Divider()
                        Label(digest.suggestion, systemImage: "lightbulb.fill")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Tap Generate to get a plain-English summary of your spending over the last 7 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await generateDigest() }
            } label: {
                Label(digest == nil ? "Generate Weekly Digest" : "Regenerate",
                      systemImage: "sparkles")
            }
            .disabled(isGeneratingDigest)
        } header: {
            SummitSectionHeader(title: "Weekly Digest", systemImage: "sparkles")
        } footer: {
            Text("Generated on-device. Nothing is sent to a server.")
        }
        .summitRowBackground()
    }

    private var smartCategorizeSection: some View {
        Section {
            if isCategorizing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        ProgressView()
                        Text("Categorizing transactions…")
                            .foregroundStyle(.secondary)
                    }
                    if let p = categorizeProgress {
                        ProgressView(value: Double(p.current), total: Double(p.total))
                        Text("\(p.current) of \(p.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else if let result = categorizeResult {
                Text(result)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Let on-device AI assign a category to every transaction that's currently uncategorized.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await runSmartCategorize() }
            } label: {
                Label("Smart Categorize Uncategorized", systemImage: "wand.and.stars")
            }
            .disabled(isCategorizing)
        } header: {
            SummitSectionHeader(title: "Smart Categorize", systemImage: "wand.and.stars")
        }
        .summitRowBackground()
    }

    private var aboutSection: some View {
        Section {
            Label("Apple Intelligence • on-device", systemImage: "lock.shield")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .summitRowBackground()
    }

    private func unavailableSection(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("AI features unavailable", systemImage: "sparkles.slash")
                    .font(.headline)
                Text(reasonText(reason))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .summitRowBackground()
    }

    private func reasonText(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to use Summit's on-device AI features."
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence. AI features require an Apple Intelligence-capable device."
        case .modelNotReady:
            return "The on-device model is still downloading. Check back in a few minutes."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    // MARK: Actions

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isAsking = true
        defer { isAsking = false }
        do {
            let service = AIInsightsService(context: context)
            let result = try await service.answer(to: q)
            if let result {
                answer = result
            } else {
                errorMessage = "I couldn't understand that question. Try rephrasing it."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generateDigest() async {
        isGeneratingDigest = true
        defer { isGeneratingDigest = false }
        do {
            let service = AIInsightsService(context: context)
            digest = try await service.weeklySummary()
            if digest == nil {
                errorMessage = "No transactions in the last 7 days to summarize."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runSmartCategorize() async {
        isCategorizing = true
        categorizeProgress = nil
        categorizeResult = nil
        defer { isCategorizing = false }
        do {
            let service = AIInsightsService(context: context)
            let updated = try await service.categorizeUncategorized { current, total in
                Task { @MainActor in
                    categorizeProgress = (current, total)
                }
            }
            categorizeResult = updated == 0
                ? "Nothing to categorize — every transaction already has a category."
                : "Categorized \(updated) transaction\(updated == 1 ? "" : "s")."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct InsightsHeroCard: View {
    let availability: SystemLanguageModel.Availability
    let digestHeadline: String?

    private var statusText: String {
        switch availability {
        case .available: return "Active"
        case .unavailable: return "Unavailable"
        }
    }
    private var statusTint: Color {
        switch availability {
        case .available: return .green
        case .unavailable: return .orange
        }
    }
    private var statusIcon: String {
        switch availability {
        case .available: return "checkmark.seal.fill"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        SummitGlassCard {
            SummitHeroHeader(
                systemImage: "sparkles",
                label: "Apple Intelligence",
                trailing: AnyView(
                    SummitChip(text: statusText, systemImage: statusIcon, tint: statusTint)
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(digestHeadline == nil ? "On-Device Insights" : "Latest Digest")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(digestHeadline ?? "Private summaries that never leave your device.")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 12) {
                Label("On-device", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Private", systemImage: "hand.raised.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Free", systemImage: "infinity")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            configuration.title
        }
    }
}

#Preview {
    AIInsightsView()
        .modelContainer(for: [
            AccountModel.self, TransactionModel.self, CategoryModel.self, CategoryGroupModel.self
        ], inMemory: true)
}
