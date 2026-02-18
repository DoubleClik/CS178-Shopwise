//
//  Untitled.swift
//  ShopwiseFrontEndUI
//
//  Created by Nicholas Castellanos on 2/2/26.
//

import SwiftUI
import Combine

@MainActor
final class AuthManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userEmail: String? = nil

    func signIn(email: String, password: String) async throws {
        guard !email.isEmpty, !password.isEmpty else {
            throw AuthError.missingFields
        }
        self.userEmail = email
        self.isSignedIn = true
    }

    func signUp(name: String, email: String, password: String) async throws {
        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
            throw AuthError.missingFields
        }
        self.userEmail = email
        self.isSignedIn = true
    }

    func signOut() {
        userEmail = nil
        isSignedIn = false
    }

    enum AuthError: LocalizedError {
        case missingFields
        var errorDescription: String? { "Please fill out all fields." }
    }
}


#Preview {
    AuthView()
        .environmentObject(AuthManager())
}
