import Foundation
import Supabase

struct Household: Decodable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let owner_user_id: UUID
    let created_at: Date
}

struct HouseholdMembership: Decodable, Sendable {
    let household_id: UUID
    let user_id: UUID
    let role: String
    let joined_at: Date
}

struct HouseholdInvite: Codable, Sendable {
    let code: String
    let household_id: UUID
    let role: String
    let created_by: UUID
    let expires_at: Date
    let used_at: Date?
    let used_by: UUID?
}

private struct InviteInsert: Encodable, Sendable {
    let code: String
    let household_id: UUID
    let role: String
    let created_by: UUID
    let expires_at: Date
}

private struct RedeemParams: Encodable, Sendable {
    let invite_code: String
}

enum HouseholdRole: String, Sendable {
    case owner
    case member
    case viewer

    var canWrite: Bool { self == .owner || self == .member }
    var canInvite: Bool { self == .owner }
}

@MainActor
@Observable
final class HouseholdService {
    static let shared = HouseholdService()

    private(set) var currentHousehold: Household?
    private(set) var currentRole: HouseholdRole?
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    private init() {}

    func refresh() async {
        guard let userID = SupabaseService.shared.currentUserID else {
            currentHousehold = nil
            currentRole = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let memberships: [HouseholdMembership] = try await SupabaseService.shared.client
                .from("household_members")
                .select()
                .eq("user_id", value: userID.uuidString.lowercased())
                .order("joined_at", ascending: false)
                .execute()
                .value

            guard let primary = memberships.first else {
                currentHousehold = nil
                currentRole = nil
                return
            }

            let households: [Household] = try await SupabaseService.shared.client
                .from("households")
                .select()
                .eq("id", value: primary.household_id.uuidString.lowercased())
                .execute()
                .value

            currentHousehold = households.first
            currentRole = HouseholdRole(rawValue: primary.role)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// All members of the current household (for settle-up attribution).
    func members() async -> [HouseholdMembership] {
        guard let household = currentHousehold else { return [] }
        do {
            return try await SupabaseService.shared.client
                .from("household_members")
                .select()
                .eq("household_id", value: household.id.uuidString.lowercased())
                .execute()
                .value
        } catch {
            return []
        }
    }

    func createInvite(role: HouseholdRole = .member, expiresInDays: Int = 7) async throws -> String {
        guard let household = currentHousehold else { throw HouseholdError.noHousehold }
        guard let userID = SupabaseService.shared.currentUserID else { throw HouseholdError.notAuthenticated }
        guard currentRole?.canInvite == true else { throw HouseholdError.notOwner }

        let code = Self.generateInviteCode()
        let expires = Date().addingTimeInterval(TimeInterval(expiresInDays) * 86_400)
        let payload = InviteInsert(code: code, household_id: household.id,
                                   role: role.rawValue, created_by: userID,
                                   expires_at: expires)
        try await SupabaseService.shared.client.from("household_invites").insert(payload).execute()
        return code
    }

    func redeemInvite(code: String) async throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw HouseholdError.invalidCode }
        let params = RedeemParams(invite_code: trimmed)
        try await SupabaseService.shared.client
            .rpc("redeem_household_invite", params: params)
            .execute()
        await refresh()
    }

    private static func generateInviteCode() -> String {
        // 8-char Crockford base32-ish alphabet, no ambiguous chars (no 0/O, 1/I/L).
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }
}

enum HouseholdError: LocalizedError {
    case notAuthenticated
    case noHousehold
    case notOwner
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Sign in first."
        case .noHousehold: return "No household available."
        case .notOwner: return "Only the household owner can create invites."
        case .invalidCode: return "Enter a valid invite code."
        }
    }
}
