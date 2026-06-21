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
            if canWrite {
                lastPushCount = try await pushAccounts(context: context, householdID: household.id)
            } else {
                lastPushCount = 0
            }
            lastPullCount = try await pullAccounts(context: context, householdID: household.id)
            lastSyncedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func pushAccounts(context: ModelContext, householdID: UUID) async throws -> Int {
        let descriptor = FetchDescriptor<AccountModel>()
        let local = try context.fetch(descriptor)

        let rows = local.map { account in
            AccountRow(
                id: account.id,
                household_id: householdID,
                name: account.name,
                type: account.type.rawValue,
                balance: account.balance,
                currency_code: account.currencyCode,
                deleted_at: nil
            )
        }

        guard !rows.isEmpty else { return 0 }

        try await SupabaseService.shared.client
            .from("accounts")
            .upsert(rows, onConflict: "id")
            .execute()

        return rows.count
    }

    private func pullAccounts(context: ModelContext, householdID: UUID) async throws -> Int {
        let response: [AccountRow] = try await SupabaseService.shared.client
            .from("accounts")
            .select()
            .eq("household_id", value: householdID.uuidString.lowercased())
            .is("deleted_at", value: nil)
            .execute()
            .value

        let existing = try context.fetch(FetchDescriptor<AccountModel>())
        var byID: [UUID: AccountModel] = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        var changed = 0
        for row in response {
            guard let type = AccountType(rawValue: row.type) else { continue }
            if let local = byID[row.id] {
                if local.name != row.name { local.name = row.name; changed += 1 }
                if local.type != type { local.type = type; changed += 1 }
                if local.balance != row.balance { local.balance = row.balance; changed += 1 }
                if local.currencyCode != row.currency_code { local.currencyCode = row.currency_code; changed += 1 }
            } else {
                let newAccount = AccountModel(
                    id: row.id,
                    name: row.name,
                    type: type,
                    balance: row.balance,
                    currencyCode: row.currency_code
                )
                context.insert(newAccount)
                byID[row.id] = newAccount
                changed += 1
            }
        }

        if changed > 0 { try context.save() }
        return response.count
    }
}
