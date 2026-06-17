import Foundation
import SwiftData
import FoundationModels

/// On-device intelligence for Summit. Two capabilities:
///   1. `suggestCategory` / `categorizeUncategorized` — pick the best matching
///      `CategoryModel` for a transaction using its merchant, amount, and memo.
///   2. `weeklySummary` — produce a structured, plain-English digest of the
///      user's recent spending.
///
/// All work is on-device via Apple's `FoundationModels` framework. Nothing is
/// sent to a server, ever.
@MainActor
struct AIInsightsService {
    let context: ModelContext

    // MARK: Availability

    static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: Categorization

    @Generable(description: "AI's pick of which budget category a transaction belongs to.")
    struct CategorySuggestion: Equatable {
        @Guide(description: "The exact `id` (UUID string) of the chosen category from the provided list. If nothing fits, return an empty string.")
        var categoryId: String

        @Guide(description: "A confidence score from 0.0 (guess) to 1.0 (certain).", .range(0.0...1.0))
        var confidence: Double

        @Guide(description: "One short sentence explaining why this category fits.")
        var reasoning: String
    }

    /// Asks the model to pick a category for a single transaction. Returns
    /// `nil` if the model can't confidently match, or if FoundationModels is
    /// unavailable on this device.
    func suggestCategory(
        for transaction: TransactionModel,
        among categories: [CategoryModel],
        minConfidence: Double = 0.5
    ) async throws -> (CategoryModel, CategorySuggestion)? {
        guard Self.isAvailable, !categories.isEmpty else { return nil }

        let catalog = categories.map { c in
            let group = c.group?.name ?? "—"
            return "\(c.id.uuidString) | \(c.name) (\(group))"
        }.joined(separator: "\n")

        let instructions = """
        You are a budgeting assistant. Pick the single best category for a transaction.
        You must return the `categoryId` exactly as it appears in the catalog. \
        If nothing is a good match, return an empty string for `categoryId` and 0 confidence.
        """

        let session = LanguageModelSession(instructions: instructions)

        let prompt = """
        Transaction:
        - Merchant: \(transaction.merchant)
        - Amount: \(transaction.amount) \(transaction.account?.currencyCode ?? "USD")
        - Memo: \(transaction.memo ?? "—")
        - Date: \(transaction.date.formatted(date: .abbreviated, time: .omitted))

        Catalog (id | name (group)):
        \(catalog)
        """

        let result = try await session.respond(to: prompt, generating: CategorySuggestion.self)
        let suggestion = result.content
        guard suggestion.confidence >= minConfidence,
              let match = categories.first(where: { $0.id.uuidString == suggestion.categoryId }) else {
            return nil
        }
        return (match, suggestion)
    }

    /// Tries to categorize every uncategorized transaction in the store.
    /// Returns the count actually updated.
    func categorizeUncategorized(progress: ((Int, Int) -> Void)? = nil) async throws -> Int {
        let uncategorized = try context.fetch(FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.category == nil }
        ))
        let categories = try context.fetch(FetchDescriptor<CategoryModel>())
        guard !uncategorized.isEmpty, !categories.isEmpty else { return 0 }

        var updated = 0
        for (index, tx) in uncategorized.enumerated() {
            progress?(index + 1, uncategorized.count)
            do {
                if let (category, _) = try await suggestCategory(for: tx, among: categories) {
                    tx.category = category
                    updated += 1
                }
            } catch {
                // Skip individual failures — one bad row shouldn't kill the batch.
                continue
            }
        }
        try context.save()
        return updated
    }

    // MARK: Weekly summary

    @Generable(description: "A short, friendly digest of recent spending.")
    struct WeeklyDigest: Equatable {
        @Guide(description: "A one-sentence headline summarising the week.")
        var headline: String

        @Guide(description: "Two to four short bullet observations about the week's spending.", .maximumCount(4))
        var bullets: [String]

        @Guide(description: "A single suggestion the user could act on this week. Empty string if nothing notable.")
        var suggestion: String
    }

    /// Builds a digest of spending for the trailing `days` window (default 7).
    /// Returns `nil` if there's nothing meaningful to summarize.
    func weeklySummary(days: Int = 7) async throws -> WeeklyDigest? {
        guard Self.isAvailable else { return nil }

        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let recent = try context.fetch(FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.date >= since }
        ))
        guard !recent.isEmpty else { return nil }

        let lines = recent.prefix(120).map { tx -> String in
            let cat = tx.category?.name ?? "Uncategorized"
            let signed = NSDecimalNumber(decimal: tx.amount).doubleValue
            return "\(tx.date.formatted(date: .abbreviated, time: .omitted)) | \(tx.merchant) | \(String(format: "%.2f", signed)) | \(cat)"
        }.joined(separator: "\n")

        let totals = totalsByCategory(recent)
        let topCategories = totals.sorted { $0.value < $1.value }.prefix(5).map { entry -> String in
            "\(entry.key): \(String(format: "%.2f", NSDecimalNumber(decimal: -entry.value).doubleValue))"
        }.joined(separator: ", ")

        let instructions = """
        You write short, warm weekly money digests for personal-finance app users. \
        Negative amounts are outflows (money spent), positive are inflows (income / refunds). \
        Be specific — mention merchants and dollar amounts. Avoid generic advice. \
        Never invent numbers.
        """
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        Past \(days) days of transactions (date | merchant | amount | category):
        \(lines)

        Top outflow categories: \(topCategories.isEmpty ? "—" : topCategories)
        """
        let result = try await session.respond(to: prompt, generating: WeeklyDigest.self)
        return result.content
    }

    // MARK: Helpers

    private func totalsByCategory(_ txns: [TransactionModel]) -> [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for tx in txns where tx.amount < 0 {
            let key = tx.category?.name ?? "Uncategorized"
            totals[key, default: 0] += tx.amount
        }
        return totals
    }
}
