import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthManager

    enum Mode { case login, signup }
    @State private var mode: Mode = .login

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemBlue).opacity(0.12).ignoresSafeArea()

            VStack {
                Spacer(minLength: 30)

                VStack(spacing: 18) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "cart")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.blue)

                        Text("ShopWise")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .bold()
                    }
                    .padding(.top, 10)

                    // Login / Sign Up toggle
                    Picker("", selection: $mode) {
                        Text("Login").tag(Mode.login)
                        Text("Sign Up").tag(Mode.signup)
                    }
                    .pickerStyle(.segmented)

                    // Fields
                    VStack(spacing: 12) {
                        if mode == .signup {
                            LabeledField(title: "Name") {
                                TextField("Enter your name", text: $name)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                            }
                        }

                        LabeledField(title: "Email") {
                            TextField("Enter your email", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                        }

                        LabeledField(title: "Password") {
                            SecureField(mode == .signup ? "Create a password" : "Enter your password",
                                        text: $password)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView() }
                            Text(mode == .signup ? "Sign Up" : "Login")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white)
                )
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    @MainActor
    private func submit() async {
        isLoading = true
        errorMessage = nil

        do {
            switch mode {
            case .login:
                try await auth.signIn(email: email, password: password)
            case .signup:
                // If you don’t have signUp yet, temporarily just sign in:
                // try await auth.signIn(email: email, password: password)

                try await auth.signUp(name: name, email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)

            content()
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
