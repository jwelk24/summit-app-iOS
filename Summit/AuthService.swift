import Foundation
import Supabase

@MainActor
enum AuthService {
    static func signUp(email: String, password: String) async throws {
        _ = try await SupabaseService.shared.client.auth.signUp(
            email: email,
            password: password
        )
    }

    static func signIn(email: String, password: String) async throws {
        _ = try await SupabaseService.shared.client.auth.signIn(
            email: email,
            password: password
        )
    }

    static func signOut() async throws {
        try await SupabaseService.shared.client.auth.signOut()
    }

    static func sendPasswordReset(email: String) async throws {
        try await SupabaseService.shared.client.auth.resetPasswordForEmail(email)
    }
}
