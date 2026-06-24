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

    var body: some View {
        NavigationStack {
            List {
                switch availability {
                case .available:
                    digestSection
                    smartCategorizeSection
                    aboutSection
                case .unavailable(let reason):
                    unavailableSection(reason)
                }
            }
            .summitListBackground()
            .navigationTitle("Insights")
            .alert("AI Error", isPresented: errorBinding, presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    // MARK: Sections

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
            Text("Weekly Digest")
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
            Text("Smart Categorize")
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
