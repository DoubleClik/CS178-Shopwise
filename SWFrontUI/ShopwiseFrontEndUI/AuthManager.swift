//
//  AuthManager.swift
//  ShopwiseFrontEndUI
//
//  Created by Nicholas Castellanos on 2/2/26.
//  Edited by Nicholas Castellanos on 2/24/26

//import SwiftUI
//import Combine
//
//@MainActor
//final class AuthManager: ObservableObject {
//    @Published var isSignedIn: Bool = false
//    @Published var userEmail: String? = nil
//
//    func signIn(email: String, password: String) async throws {
//        guard !email.isEmpty, !password.isEmpty else {
//            throw AuthError.missingFields
//        }
//        self.userEmail = email
//        self.isSignedIn = true
//    }
//
//    func signUp(name: String, email: String, password: String) async throws {
//        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
//            throw AuthError.missingFields
//        }
//        self.userEmail = email
//        self.isSignedIn = true
//    }
//
//    func signOut() {
//        userEmail = nil
//        isSignedIn = false
//    }
//
//    enum AuthError: LocalizedError {
//        case missingFields
//        var errorDescription: String? { "Please fill out all fields." }
//    }
//}
//
//
//#Preview {
//    AuthView()
//        .environmentObject(AuthManager())
//}

import Foundation
import SwiftUI
import Combine

struct PostgrestError: Decodable {
    let message: String?
    let details: String?
    let hint: String?
    let code: String?
}

@MainActor
final class AuthManager: ObservableObject {
    // MARK: - Supabase config
    private let supabaseURL = URL(string: "https://vpmxdkrwqxgullnducey.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZwbXhka3J3cXhndWxsbmR1Y2V5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE0NDQ5ODMsImV4cCI6MjA4NzAyMDk4M30.NYievlganIUF4tVQvgK8NAaMAk2_y6NHnijvbuiWKCw"

    // MARK: - Published state
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isSignedIn: Bool = false
    @Published var userEmail: String? = nil

    // Tokens
    private(set) var accessToken: String? = nil
    private(set) var refreshToken: String? = nil

    // Simple token persistence (fast). Use Keychain later if you want.
    private let accessTokenKey = "sb_access_token"
    private let refreshTokenKey = "sb_refresh_token"

    init() {
        loadTokensFromStorage()
        Task { await restoreSession() }
    }

    // MARK: - Public API
    
    private struct SignUpBody: Codable {
        let email: String
        let password: String
        let data: Meta

        struct Meta: Codable {
            let name: String
        }
    }
    
    func signIn(email: String, password: String) async throws {
        try await runAuthCall {
            var comps = URLComponents(
                url: self.supabaseURL.appendingPathComponent("auth/v1/token"),
                resolvingAgainstBaseURL: false
            )!
            comps.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
            let url = comps.url!

            let body: [String: String] = ["email": email, "password": password]

            let (data, _) = try await self.request(
                url: url,
                method: "POST",
                jsonBody: body,
                bearerToken: nil
            )
            let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
            self.applySession(session)
            self.userEmail = email
        }
    }
    
    enum AuthError: LocalizedError {
        case emailConfirmationRequired

        var errorDescription: String? {
            switch self {
            case .emailConfirmationRequired:
                return "Sign up succeeded — please confirm your email, then log in."
            }
        }
    }

    func signUp(name: String, email: String, password: String) async throws {
        try await runAuthCall {
            let url = self.supabaseURL.appendingPathComponent("auth/v1/signup")
            let body = SignUpBody(
                email: email,
                password: password,
                data: .init(name: name)
            )

            let (data, _) = try await self.request(
              url: url,
              method: "POST",
              jsonBody: body,
              bearerToken: nil
            )

            if let session = try? JSONDecoder().decode(SupabaseSession.self, from: data),
               !session.access_token.isEmpty {
                self.applySession(session)
                self.userEmail = email
            } else {
                self.userEmail = email
                throw AuthError.emailConfirmationRequired
            }
        }
    }

    func signOut() async {
        do {
            try await runAuthCall {
                guard let token = self.accessToken else {
                    self.clearSession()
                    return
                }

                let url = self.supabaseURL.appendingPathComponent("auth/v1/logout")

                _ = try await self.request(
                    url: url,
                    method: "POST",
                    jsonBody: nil as [String:String]?,
                    bearerToken: token
                )

                self.clearSession()
            }
        } catch {
            // Even if server logout fails, clear local session
            self.clearSession()
        }
    }

    /// Called on app launch: validate token and fetch /auth/v1/user
    func restoreSession() async {
        guard let token = accessToken else {
            isSignedIn = false
            return
        }

        do {
            let url = supabaseURL.appendingPathComponent("auth/v1/user")
            let (data, _) = try await request(
                url: url,
                method: "GET",
                jsonBody: nil as [String:String]?,
                bearerToken: token
            )
            let user = try JSONDecoder().decode(SupabaseUser.self, from: data)
            self.userEmail = user.email
            self.isSignedIn = true
        } catch {
            // token might be expired -> try refresh
            if let refreshed = try? await refreshSession() {
                self.userEmail = refreshed.user?.email
                self.isSignedIn = true
            } else {
                clearSession()
            }
        }
    }

    // MARK: - Refresh

    private func refreshSession() async throws -> SupabaseSession {
        guard let rToken = refreshToken else { throw URLError(.userAuthenticationRequired) }

        var comps = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        let url = comps.url!

        let body = ["refresh_token": rToken]

        let (data, _) = try await request(
            url: url,
            method: "POST",
            jsonBody: body,
            bearerToken: nil
        )

        let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
        applySession(session)
        return session
    }

    // MARK: - Helpers

    private func runAuthCall<T>(_ work: () async throws -> T) async throws -> T {
        self.errorMessage = nil
        self.isLoading = true
        defer { self.isLoading = false }

        do {
            return try await work()
        } catch {
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    private func applySession(_ session: SupabaseSession) {
        self.accessToken = session.access_token
        self.refreshToken = session.refresh_token
        saveTokensToStorage()
        self.isSignedIn = true
    }

    private func clearSession() {
        self.accessToken = nil
        self.refreshToken = nil
        self.userEmail = nil
        self.isSignedIn = false
        deleteTokensFromStorage()
    }

    private func request<T: Encodable>(
        url: URL,
        method: String,
        jsonBody: T?,
        bearerToken: String?
    ) async throws -> (Data, HTTPURLResponse) {

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let jsonBody {
            req.httpBody = try JSONEncoder().encode(jsonBody)
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if !(200...299).contains(http.statusCode) {

            // ✅ 1) Print raw body in Xcode console
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            print("❌ Supabase HTTP \(http.statusCode) \(url.absoluteString)")
            print("❌ Body: \(raw)")

            // ✅ 2) Try PostgREST error first
            if let pg = try? JSONDecoder().decode(PostgrestError.self, from: data),
               let msg = pg.message, !msg.isEmpty {
                var full = msg
                if let details = pg.details, !details.isEmpty { full += "\nDetails: \(details)" }
                if let hint = pg.hint, !hint.isEmpty { full += "\nHint: \(hint)" }

                throw NSError(domain: "Supabase", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: full])
            }

            // ✅ 3) Then try auth-style error
            if let sb = try? JSONDecoder().decode(SupabaseError.self, from: data) {
                let msg = sb.msg ?? sb.error_description ?? sb.error ?? ""
                if !msg.isEmpty {
                    throw NSError(domain: "Supabase", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: msg])
                }
            }

            // ✅ 4) Last resort: show raw response
            throw NSError(domain: "Supabase", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)\n\(raw)"])
        }

        return (data, http)
    }

    private func prettyError(_ error: Error) -> String {
        (error as NSError).localizedDescription
    }

    private func saveTokensToStorage() {
        UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
        UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
    }

    private func loadTokensFromStorage() {
        accessToken = UserDefaults.standard.string(forKey: accessTokenKey)
        refreshToken = UserDefaults.standard.string(forKey: refreshTokenKey)
    }

    private func deleteTokensFromStorage() {
        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
    }
}

// MARK: - Models (Supabase Auth JSON)

struct SupabaseSession: Codable {
    let access_token: String
    let refresh_token: String
    let token_type: String?
    let expires_in: Int?
    let user: SupabaseUser?
}

struct SupabaseUser: Codable {
    let id: String?
    let email: String?
}

struct SupabaseError: Codable {
    let error: String?
    let error_description: String?
    let msg: String?
}


// ------ Walmart Items Fetcher ------ //

extension AuthManager {
    func fetchWalmartItems(
        search: String? = nil,
        ingredientOnly: Bool? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [WalmartItem] {

        let tableName = "classified_ingredients_aa"  // <-- CHANGE THIS

        let base = supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent(tableName)

        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [
            URLQueryItem(
                name: "select",
                value: "id,name,ingredient,classifiers,retail_price,thumbnailImage,mediumImage,largeImage,color"
            ),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "order", value: "id.asc")
        ]

        if let s = search?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            q.append(URLQueryItem(name: "name", value: "ilike.*\(s)*"))
        }

        if let ingredientOnly {
            // PostgREST boolean filter
            q.append(URLQueryItem(name: "ingredient", value: "eq.\(ingredientOnly ? "true" : "false")"))
        }

        comps.queryItems = q
        guard let url = comps.url else { throw URLError(.badURL) }

        let (data, _) = try await request(
            url: url,
            method: "GET",
            jsonBody: Optional<String>.none,
            bearerToken: accessToken
        )

        return try JSONDecoder().decode([WalmartItem].self, from: data)
    }
}

// --- Recpie Fetcher --- //

extension AuthManager {
    func fetchRecipes(search: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> [RecipeRow] {
        let base = supabaseURL
            .appendingPathComponent("rest/v1/Recipes_Kaggle")

        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(
                name: "select",
                value: "id,Title,Ingredients,Instructions,Image_Name,Cleaned_Ingredients,image_url"
            ),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "order", value: "id.asc")
        ]

        if let s = search?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            queryItems.append(URLQueryItem(name: "Title", value: "ilike.*\(s)*"))
        }

        comps.queryItems = queryItems

        let (data, _) = try await request(
            url: comps.url!,
            method: "GET",
            jsonBody: Optional<String>.none,
            bearerToken: accessToken
        )

        return try JSONDecoder().decode([RecipeRow].self, from: data)
    }
}
