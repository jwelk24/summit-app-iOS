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
}
