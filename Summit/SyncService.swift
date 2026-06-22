import Foundation
import SwiftData
import Supabase

private struct AccountRow: Codable, Sendable {
    let id: UUID
    let household_id: UUID
    let name: String
    let type: String
    let balance: Decimal
    let currency_code: String
    let deleted_at: Date?
}

private struct CategoryGroupRow: Codable, Sendable {
    let id: UUID
    let household_id: UUID
    let name: String
    let sort: Int
    let deleted_at: Date?
}

private struct CategoryRow: Codable, Sendable {
    let id: UUID
    let household_id: UUID
    let group_id: UUID?
    let linked_account_id: UUID?
    let name: String
    let sort: Int
    let deleted_at: Date?
}

private struct TransactionRow: Codable, Sendable {
    let id: UUID
    let household_id: UUID
    let account_id: UUID?
    let category_id: UUID?
    let date: Date
    let amount: Decimal
    let merchant: String
    let memo: String?
    let cleared: Bool
    let flag_color: String?
    let deleted_at: Date?
}

private struct TransactionSplitRow: Codable, Sendable {
    let id: UUID
    let household_id: UUID
    let transaction_id: UUID
    let category_id: UUID?
    let amount: Decimal
    let memo: String?
    let deleted_at: Date?
}

enum SyncTable {
    static let transactions = "transactions"
}

@MainActor
enum SoftDelete {
    static func markTransactionDeleted(_ tx: TransactionModel, context: ModelContext) {
        let tombstone = SoftDeleteTombstone(table: SyncTable.transactions, recordID: tx.id)
        context.insert(tombstone)
        context.delete(tx)
    }
}

enum SyncError: LocalizedError {
    case notAuthenticated
    case noHousehold
    case readOnlyRole

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Sign in to sync."
        case .noHousehold: return "No household found. Try reloading."
        case .readOnlyRole: return "Your role is viewer — read-only. Ask the household owner to upgrade your role."
        }
    }
}

@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    private(set) var isSyncing: Bool = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    private(set) var lastPushCount: Int = 0
    private(set) var lastPullCount: Int = 0

    private init() {}

    private let throttleInterval: TimeInterval = 15

    func syncIfDue(context: ModelContext) async {
        if let last = lastSyncedAt, Date().timeIntervalSince(last) < throttleInterval { return }
        await syncAccounts(context: context)
    }

    func syncAccounts(context: ModelContext) async {
        guard Premium.isActive else { return }
        guard SupabaseService.shared.isAuthenticated else {
            lastError = SyncError.notAuthenticated.localizedDescription
            return
        }
        guard let household = HouseholdService.shared.currentHousehold else {
            lastError = SyncError.noHousehold.localizedDescription
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        lastError = nil

        do {
            let canWrite = HouseholdService.shared.currentRole?.canWrite ?? false
            var pushed = 0
            var pulled = 0

            if canWrite {
                pushed += try await pushAccounts(context: context, householdID: household.id)
                pushed += try await pushCategoryGroups(context: context, householdID: household.id)
                pushed += try await pushCategories(context: context, householdID: household.id)
                pushed += try await pushTransactions(context: context, householdID: household.id)
                pushed += try await pushTransactionSplits(context: context, householdID: household.id)
                pushed += try await pushDeletions(context: context, householdID: household.id)
            }

            pulled += try await pullAccounts(context: context, householdID: household.id)
            pulled += try await pullCategoryGroups(context: context, householdID: household.id)
            pulled += try await pullCategories(context: context, householdID: household.id)
            pulled += try await pullTransactions(context: context, householdID: household.id)
            pulled += try await pullTransactionSplits(context: context, householdID: household.id)

            lastPushCount = pushed
            lastPullCount = pulled
            lastSyncedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Accounts

    private func pushAccounts(context: ModelContext, householdID: UUID) async throws -> Int {
        let local = try context.fetch(FetchDescriptor<AccountModel>())
        let rows = local.map { a in
            AccountRow(id: a.id, household_id: householdID, name: a.name, type: a.type.rawValue,
                       balance: a.balance, currency_code: a.currencyCode, deleted_at: nil)
        }
        guard !rows.isEmpty else { return 0 }
        try await SupabaseService.shared.client.from("accounts").upsert(rows, onConflict: "id").execute()
        return rows.count
    }

    private func pullAccounts(context: ModelContext, householdID: UUID) async throws -> Int {
        let rows: [AccountRow] = try await SupabaseService.shared.client
            .from("accounts").select()
            .eq("household_id", value: householdID.uuidString.lowercased())
            .is("deleted_at", value: nil).execute().value

        var byID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<AccountModel>()).map { ($0.id, $0) })
        var changed = 0
        for row in rows {
            guard let type = AccountType(rawValue: row.type) else { continue }
            if let local = byID[row.id] {
                if local.name != row.name { local.name = row.name; changed += 1 }
                if local.type != type { local.type = type; changed += 1 }
                if local.balance != row.balance { local.balance = row.balance; changed += 1 }
                if local.currencyCode != row.currency_code { local.currencyCode = row.currency_code; changed += 1 }
            } else {
                let a = AccountModel(id: row.id, name: row.name, type: type, balance: row.balance, currencyCode: row.currency_code)
                context.insert(a)
                byID[row.id] = a
                changed += 1
            }
        }
        if changed > 0 { try context.save() }
        return rows.count
    }

    // MARK: - Category Groups

    private func pushCategoryGroups(context: ModelContext, householdID: UUID) async throws -> Int {
        let local = try context.fetch(FetchDescriptor<CategoryGroupModel>())
        let rows = local.map { g in
            CategoryGroupRow(id: g.id, household_id: householdID, name: g.name, sort: g.sort, deleted_at: nil)
        }
        guard !rows.isEmpty else { return 0 }
        try await SupabaseService.shared.client.from("category_groups").upsert(rows, onConflict: "id").execute()
        return rows.count
    }

    private func pullCategoryGroups(context: ModelContext, householdID: UUID) async throws -> Int {
        let rows: [CategoryGroupRow] = try await SupabaseService.shared.client
            .from("category_groups").select()
            .eq("household_id", value: householdID.uuidString.lowercased())
            .is("deleted_at", value: nil).execute().value

        var byID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CategoryGroupModel>()).map { ($0.id, $0) })
        var changed = 0
        for row in rows {
            if let local = byID[row.id] {
                if local.name != row.name { local.name = row.name; changed += 1 }
                if local.sort != row.sort { local.sort = row.sort; changed += 1 }
            } else {
                let g = CategoryGroupModel(id: row.id, name: row.name, sort: row.sort)
                context.insert(g)
                byID[row.id] = g
                changed += 1
            }
        }
        if changed > 0 { try context.save() }
        return rows.count
    }

    // MARK: - Categories

    private func pushCategories(context: ModelContext, householdID: UUID) async throws -> Int {
        let local = try context.fetch(FetchDescriptor<CategoryModel>())
        let rows = local.map { c in
            CategoryRow(id: c.id, household_id: householdID, group_id: c.group?.id,
                        linked_account_id: c.linkedAccount?.id, name: c.name, sort: c.sort, deleted_at: nil)
        }
        guard !rows.isEmpty else { return 0 }
        try await SupabaseService.shared.client.from("categories").upsert(rows, onConflict: "id").execute()
        return rows.count
    }

    private func pullCategories(context: ModelContext, householdID: UUID) async throws -> Int {
        let rows: [CategoryRow] = try await SupabaseService.shared.client
            .from("categories").select()
            .eq("household_id", value: householdID.uuidString.lowercased())
            .is("deleted_at", value: nil).execute().value

        let groupsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CategoryGroupModel>()).map { ($0.id, $0) })
        let accountsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<AccountModel>()).map { ($0.id, $0) })
        var byID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CategoryModel>()).map { ($0.id, $0) })
        var changed = 0
        for row in rows {
            let group = row.group_id.flatMap { groupsByID[$0] }
            let linkedAccount = row.linked_account_id.flatMap { accountsByID[$0] }
            if let local = byID[row.id] {
                if local.name != row.name { local.name = row.name; changed += 1 }
                if local.sort != row.sort { local.sort = row.sort; changed += 1 }
                if local.group?.id != row.group_id { local.group = group; changed += 1 }
                if local.linkedAccount?.id != row.linked_account_id { local.linkedAccount = linkedAccount; changed += 1 }
            } else {
                let c = CategoryModel(id: row.id, name: row.name, sort: row.sort, group: group, linkedAccount: linkedAccount)
                context.insert(c)
                byID[row.id] = c
                changed += 1
            }
        }
        if changed > 0 { try context.save() }
        return rows.count
    }

    // MARK: - Transactions

    private func pushTransactions(context: ModelContext, householdID: UUID) async throws -> Int {
        let local = try context.fetch(FetchDescriptor<TransactionModel>())
        let rows = local.map { t in
            TransactionRow(id: t.id, household_id: householdID, account_id: t.account?.id, category_id: t.category?.id,
                           date: t.date, amount: t.amount, merchant: t.merchant, memo: t.memo,
                           cleared: t.cleared, flag_color: t.flagColor, deleted_at: nil)
        }
        guard !rows.isEmpty else { return 0 }
        try await SupabaseService.shared.client.from("transactions").upsert(rows, onConflict: "id").execute()
        return rows.count
    }

    private func pullTransactions(context: ModelContext, householdID: UUID) async throws -> Int {
        let rows: [TransactionRow] = try await SupabaseService.shared.client
            .from("transactions").select()
            .eq("household_id", value: householdID.uuidString.lowercased())
            .execute().value

        let accountsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<AccountModel>()).map { ($0.id, $0) })
        let categoriesByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CategoryModel>()).map { ($0.id, $0) })
        var byID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TransactionModel>()).map { ($0.id, $0) })
        var changed = 0
        for row in rows {
            if row.deleted_at != nil {
                if let local = byID[row.id] {
                    context.delete(local)
                    byID.removeValue(forKey: row.id)
                    changed += 1
                }
                continue
            }
            let account = row.account_id.flatMap { accountsByID[$0] }
            let category = row.category_id.flatMap { categoriesByID[$0] }
            if let local = byID[row.id] {
                if local.date != row.date { local.date = row.date; changed += 1 }
                if local.amount != row.amount { local.amount = row.amount; changed += 1 }
                if local.merchant != row.merchant { local.merchant = row.merchant; changed += 1 }
                if local.memo != row.memo { local.memo = row.memo; changed += 1 }
                if local.cleared != row.cleared { local.cleared = row.cleared; changed += 1 }
                if local.flagColor != row.flag_color { local.flagColor = row.flag_color; changed += 1 }
                if local.account?.id != row.account_id { local.account = account; changed += 1 }
                if local.category?.id != row.category_id { local.category = category; changed += 1 }
            } else {
                let t = TransactionModel(id: row.id, date: row.date, amount: row.amount, merchant: row.merchant,
                                         memo: row.memo, cleared: row.cleared, flagColor: row.flag_color,
                                         account: account, category: category)
                context.insert(t)
                byID[row.id] = t
                changed += 1
            }
        }
        if changed > 0 { try context.save() }
        return rows.count
    }

    // MARK: - Deletions

    private struct DeletedAtUpdate: Encodable, Sendable {
        let deleted_at: Date
    }

    private func pushDeletions(context: ModelContext, householdID: UUID) async throws -> Int {
        let tombstones = try context.fetch(FetchDescriptor<SoftDeleteTombstone>())
        guard !tombstones.isEmpty else { return 0 }

        let now = Date()
        let payload = DeletedAtUpdate(deleted_at: now)
        var pushed = 0

        for tombstone in tombstones {
            try await SupabaseService.shared.client
                .from(tombstone.table)
                .update(payload)
                .eq("id", value: tombstone.recordID.uuidString.lowercased())
                .eq("household_id", value: householdID.uuidString.lowercased())
                .execute()
            context.delete(tombstone)
            pushed += 1
        }
        if pushed > 0 { try context.save() }
        return pushed
    }

    // MARK: - Transaction Splits

    private func pushTransactionSplits(context: ModelContext, householdID: UUID) async throws -> Int {
        let local = try context.fetch(FetchDescriptor<TransactionSplitModel>())
        let rows: [TransactionSplitRow] = local.compactMap { s in
            guard let txID = s.transaction?.id else { return nil }
            return TransactionSplitRow(id: s.id, household_id: householdID, transaction_id: txID,
                                       category_id: s.category?.id, amount: s.amount, memo: s.memo, deleted_at: nil)
        }
        guard !rows.isEmpty else { return 0 }
        try await SupabaseService.shared.client.from("transaction_splits").upsert(rows, onConflict: "id").execute()
        return rows.count
    }

    private func pullTransactionSplits(context: ModelContext, householdID: UUID) async throws -> Int {
        let rows: [TransactionSplitRow] = try await SupabaseService.shared.client
            .from("transaction_splits").select()
            .eq("household_id", value: householdID.uuidString.lowercased())
            .is("deleted_at", value: nil).execute().value

        let txsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TransactionModel>()).map { ($0.id, $0) })
        let categoriesByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CategoryModel>()).map { ($0.id, $0) })
        var byID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TransactionSplitModel>()).map { ($0.id, $0) })
        var changed = 0
        for row in rows {
            guard let tx = txsByID[row.transaction_id] else { continue }
            let category = row.category_id.flatMap { categoriesByID[$0] }
            if let local = byID[row.id] {
                if local.amount != row.amount { local.amount = row.amount; changed += 1 }
                if local.memo != row.memo { local.memo = row.memo; changed += 1 }
                if local.transaction?.id != row.transaction_id { local.transaction = tx; changed += 1 }
                if local.category?.id != row.category_id { local.category = category; changed += 1 }
            } else {
                let s = TransactionSplitModel(id: row.id, amount: row.amount, memo: row.memo, transaction: tx, category: category)
                context.insert(s)
                byID[row.id] = s
                changed += 1
            }
        }
        if changed > 0 { try context.save() }
        return rows.count
    }
}
