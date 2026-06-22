import SwiftUI
import SwiftData

struct AuthView: View {
    enum Mode { case signIn, signUp }

    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private let supabase = SupabaseService.shared
    private let household = HouseholdService.shared
    private let sync = SyncService.shared

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if supabase.isAuthenticated {
            signedInView
        } else {
            signInForm
        }
    }

    private var signedInView: some View {
        NavigationStack {
            Form {
                Section("Signed in") {
                    LabeledContent("Email", value: supabase.currentEmail ?? "—")
                }

                Section("Household") {
                    if household.isLoading {
                        ProgressView()
                    } else if let h = household.currentHousehold {
                        LabeledContent("Name", value: h.name)
                        LabeledContent("Role", value: household.currentRole?.rawValue.capitalized ?? "—")
                        LabeledContent("ID", value: h.id.uuidString)
                            .font(.caption.monospaced())
                    } else {
                        Text("No household found.")
                            .foregroundStyle(.secondary)
                    }
                    if let err = household.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                    Button("Reload") {
                        Task { await household.refresh() }
                    }
                }

                Section("Sync") {
                    Button {
                        Task { await sync.syncAccounts(context: modelContext) }
                    } label: {
                        HStack {
                            if sync.isSyncing { ProgressView() }
                            Text(sync.isSyncing ? "Syncing…" : "Sync Now")
                        }
                    }
                    .disabled(sync.isSyncing || household.currentHousehold == nil)

                    if let last = sync.lastSyncedAt {
                        LabeledContent("Last sync", value: last.formatted(date: .omitted, time: .shortened))
                    }
                    LabeledContent("Pushed", value: "\(sync.lastPushCount)")
                    LabeledContent("Pulled", value: "\(sync.lastPullCount)")
                    if let err = sync.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            try? await AuthService.signOut()
                        }
                    }
                }
            }
            .navigationTitle("Summit Sync")
            .task {
                await supabase.loadUser()
                await household.refresh()
            }
        }
    }

    private var signInForm: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        Text("Sign In").tag(Mode.signIn)
                        Text("Sign Up").tag(Mode.signUp)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Account") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if let infoMessage {
                    Section {
                        Text(infoMessage)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking {
                                ProgressView()
                            } else {
                                Text(mode == .signIn ? "Sign In" : "Create Account")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            Task { await sendReset() }
                        }
                        .disabled(email.isEmpty)
                    }
                }
            }
            .navigationTitle("Summit Sync")
        }
    }

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 6 && !isWorking
    }

    private func submit() async {
        errorMessage = nil
        infoMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn:
                try await AuthService.signIn(email: email, password: password)
            case .signUp:
                try await AuthService.signUp(email: email, password: password)
                infoMessage = "Check your email to confirm your account, then sign in."
                mode = .signIn
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendReset() async {
        errorMessage = nil
        infoMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await AuthService.sendPasswordReset(email: email)
            infoMessage = "Password reset email sent."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AuthView()
}
