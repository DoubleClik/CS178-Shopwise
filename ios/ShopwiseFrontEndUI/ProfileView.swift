import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject private var cartStore: CartStore
    @Environment(\.openURL) private var openURL

    @State private var showChangePassword = false
    @State private var showDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String? = nil

    var body: some View {
        List {
            Section("Account") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.primary)

                    VStack(alignment: .leading) {
                        Text(greetingText)
                            .font(.headline)
                        Text(auth.userEmail ?? "No email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)

                // Change password — pushes to inline view
                NavigationLink {
                    ChangePasswordView()
                } label: {
                    Label("Change Password", systemImage: "lock.rotation")
                }
            }

            Section("Preferences") {
                NavigationLink {
                    OnboardingSurveyView()
                } label: {
                    Label("Edit Diet & Allergies", systemImage: "slider.horizontal.3")
                }
            }

            Section("Settings") {
                Button("Location Services") {
                    openAppSettings()
                }
            }

            Section("App Info") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Text("Sign Out")
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        if isDeletingAccount { ProgressView() }
                        Text("Delete Account")
                    }
                }
                .disabled(isDeletingAccount)

                if let err = deleteError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Deleting your account is permanent and cannot be undone.")
                    .font(.caption)
            }
        }
        .navigationTitle("Account & Settings")
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete My Account", role: .destructive) {
                Task { await submitDeleteAccount() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and all your data. This cannot be undone.")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func submitDeleteAccount() async {
        isDeletingAccount = true
        deleteError = nil
        do {
            try await auth.deleteAccount()
        } catch {
            deleteError = error.localizedDescription
            isDeletingAccount = false
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let version, let build { return "\(version) (\(build))" }
        return version ?? "1.0"
    }

    private var greetingText: String {
        if let name = auth.userName,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "Hello"
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

// MARK: - Change Password screen

struct ChangePasswordView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var success = false
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            Section {
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
            } footer: {
                Text("Minimum 6 characters.")
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if isLoading { ProgressView() }
                        Text("Update Password")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || newPassword.isEmpty || confirmPassword.isEmpty)
            }

            if success {
                Section {
                    Label("Password updated successfully!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let err = errorMessage {
                Section {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func submit() async {
        errorMessage = nil
        success = false

        guard newPassword == confirmPassword else {
            errorMessage = "Passwords don't match."
            return
        }
        guard newPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isLoading = true
        do {
            try await auth.changePassword(to: newPassword)
            success = true
            newPassword = ""
            confirmPassword = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
