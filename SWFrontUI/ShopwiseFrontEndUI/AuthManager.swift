//
//import Foundation
//import CoreLocation
//import SwiftUI
//import Combine
//
//struct PostgrestError: Decodable {
//    let message: String?
//    let details: String?
//    let hint: String?
//    let code: String?
//}
//
//@MainActor
//final class AuthManager: ObservableObject {
//    // MARK: - Supabase config
//    private let supabaseURL = URL(string: "https://vpmxdkrwqxgullnducey.supabase.co")!
//    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZwbXhka3J3cXhndWxsbmR1Y2V5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE0NDQ5ODMsImV4cCI6MjA4NzAyMDk4M30.NYievlganIUF4tVQvgK8NAaMAk2_y6NHnijvbuiWKCw"
//
//    // MARK: - Published state
//    @Published var isLoading: Bool = false
//    @Published var errorMessage: String? = nil
//    @Published var isSignedIn: Bool = false
//    @Published var userEmail: String? = nil
//    @Published var userID: String? = nil
//    @Published var userName: String? = nil
//
//    // Tokens
//    private(set) var accessToken: String? = nil
//    private(set) var refreshToken: String? = nil
//
//    // Simple token persistence (fast). Use Keychain later if you want.
//    private let accessTokenKey = "sb_access_token"
//    private let refreshTokenKey = "sb_refresh_token"
//
//    init() {
//        loadTokensFromStorage()
//        Task { await restoreSession() }
//    }
//
//    // MARK: - Public API
//    
//    private struct SignUpBody: Codable {
//        let email: String
//        let password: String
//        let data: Meta
//
//        struct Meta: Codable {
//            let name: String
//        }
//    }
//    
//    func signIn(email: String, password: String) async throws {
//        try await runAuthCall {
//            var comps = URLComponents(
//                url: self.supabaseURL.appendingPathComponent("auth/v1/token"),
//                resolvingAgainstBaseURL: false
//            )!
//            comps.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
//            let url = comps.url!
//
//            let body: [String: String] = ["email": email, "password": password]
//
//            let (data, _) = try await self.request(
//                url: url,
//                method: "POST",
//                jsonBody: body,
//                bearerToken: nil
//            )
//            let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
//            self.applySession(session)
//            self.userEmail = email
//            self.userID = session.user?.id
//            self.userName = session.user?.user_metadata?.name
//        }
//    }
//    
//    enum AuthError: LocalizedError {
//        case emailConfirmationRequired
//
//        var errorDescription: String? {
//            switch self {
//            case .emailConfirmationRequired:
//                return "Sign up succeeded — please confirm your email, then log in."
//            }
//        }
//    }
//
//    func signUp(name: String, email: String, password: String) async throws {
//        try await runAuthCall {
//            let url = self.supabaseURL.appendingPathComponent("auth/v1/signup")
//            let body = SignUpBody(
//                email: email,
//                password: password,
//                data: .init(name: name)
//            )
//
//            let (data, _) = try await self.request(
//              url: url,
//              method: "POST",
//              jsonBody: body,
//              bearerToken: nil
//            )
//
//            if let session = try? JSONDecoder().decode(SupabaseSession.self, from: data),
//               !session.access_token.isEmpty {
//                self.applySession(session)
//                self.userEmail = email
//                self.userID = session.user?.id
//            } else {
//                self.userEmail = email
//                throw AuthError.emailConfirmationRequired
//            }
//        }
//    }
//
//    func signOut() async {
//        do {
//            try await runAuthCall {
//                guard let token = self.accessToken else {
//                    self.clearSession()
//                    return
//                }
//
//                let url = self.supabaseURL.appendingPathComponent("auth/v1/logout")
//
//                _ = try await self.request(
//                    url: url,
//                    method: "POST",
//                    jsonBody: nil as [String:String]?,
//                    bearerToken: token
//                )
//
//                self.clearSession()
//            }
//        } catch {
//            // Even if server logout fails, clear local session
//            self.clearSession()
//        }
//    }
//
//    /// Called on app launch: validate token and fetch /auth/v1/user
//    func restoreSession() async {
//        guard let token = accessToken else {
//            isSignedIn = false
//            return
//        }
//
//        do {
//            let url = supabaseURL.appendingPathComponent("auth/v1/user")
//            let (data, _) = try await request(
//                url: url,
//                method: "GET",
//                jsonBody: nil as [String:String]?,
//                bearerToken: token
//            )
//            let user = try JSONDecoder().decode(SupabaseUser.self, from: data)
//            self.userEmail = user.email
//            self.isSignedIn = true
//            self.userID = user.id
//            self.userName = user.user_metadata?.name
//        } catch {
//            // token might be expired -> try refresh
//            if let refreshed = try? await refreshSession() {
//                self.userEmail = refreshed.user?.email
//                self.isSignedIn = true
//                self.userID = refreshed.user?.id
//                self.userName = refreshed.user?.user_metadata?.name
//            } else {
//                clearSession()
//            }
//        }
//    }
//
//    // MARK: - Refresh
//
//    private func refreshSession() async throws -> SupabaseSession {
//        guard let rToken = refreshToken else { throw URLError(.userAuthenticationRequired) }
//
//        var comps = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
//        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
//        let url = comps.url!
//
//        let body = ["refresh_token": rToken]
//
//        let (data, _) = try await request(
//            url: url,
//            method: "POST",
//            jsonBody: body,
//            bearerToken: nil
//        )
//
//        let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
//        applySession(session)
//        return session
//    }
//
//    // MARK: - Helpers
//
//    private func runAuthCall<T>(_ work: () async throws -> T) async throws -> T {
//        self.errorMessage = nil
//        self.isLoading = true
//        defer { self.isLoading = false }
//
//        do {
//            return try await work()
//        } catch {
//            self.errorMessage = error.localizedDescription
//            throw error
//        }
//    }
//
//    private func applySession(_ session: SupabaseSession) {
//        self.accessToken = session.access_token
//        self.refreshToken = session.refresh_token
//        self.userID = session.user?.id
//        self.userName = session.user?.user_metadata?.name
//        saveTokensToStorage()
//        self.isSignedIn = true
//    }
//
//    private func clearSession() {
//        self.accessToken = nil
//        self.refreshToken = nil
//        self.userEmail = nil
//        self.userID = nil
//        self.userName = nil
//        self.isSignedIn = false
//        deleteTokensFromStorage()
//    }
//
//    private func request<T: Encodable>(
//        url: URL,
//        method: String,
//        jsonBody: T?,
//        bearerToken: String?,
//        extraHeaders: [String: String] = [:]
//    ) async throws -> (Data, HTTPURLResponse) {
//
//        var req = URLRequest(url: url)
//        req.httpMethod = method
//        req.setValue(anonKey, forHTTPHeaderField: "apikey")
//        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
//
//        if let bearerToken {
//            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
//        }
//
//        for (key, value) in extraHeaders {
//            req.setValue(value, forHTTPHeaderField: key)
//        }
//        
//        if let jsonBody {
//            req.httpBody = try JSONEncoder().encode(jsonBody)
//        }
//
//        let (data, resp) = try await URLSession.shared.data(for: req)
//        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
//
//        if !(200...299).contains(http.statusCode) {
//
//            // ✅ 1) Print raw body in Xcode console
//            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
//            print("❌ Supabase HTTP \(http.statusCode) \(url.absoluteString)")
//            print("❌ Body: \(raw)")
//
//            // ✅ 2) Try PostgREST error first
//            if let pg = try? JSONDecoder().decode(PostgrestError.self, from: data),
//               let msg = pg.message, !msg.isEmpty {
//                var full = msg
//                if let details = pg.details, !details.isEmpty { full += "\nDetails: \(details)" }
//                if let hint = pg.hint, !hint.isEmpty { full += "\nHint: \(hint)" }
//
//                throw NSError(domain: "Supabase", code: http.statusCode,
//                              userInfo: [NSLocalizedDescriptionKey: full])
//            }
//
//            // ✅ 3) Then try auth-style error
//            if let sb = try? JSONDecoder().decode(SupabaseError.self, from: data) {
//                let msg = sb.msg ?? sb.error_description ?? sb.error ?? ""
//                if !msg.isEmpty {
//                    throw NSError(domain: "Supabase", code: http.statusCode,
//                                  userInfo: [NSLocalizedDescriptionKey: msg])
//                }
//            }
//
//            // ✅ 4) Last resort: show raw response
//            throw NSError(domain: "Supabase", code: http.statusCode,
//                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)\n\(raw)"])
//        }
//
//        return (data, http)
//    }
//
//    private func prettyError(_ error: Error) -> String {
//        (error as NSError).localizedDescription
//    }
//
//    private func saveTokensToStorage() {
//        UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
//        UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
//    }
//
//    private func loadTokensFromStorage() {
//        accessToken = UserDefaults.standard.string(forKey: accessTokenKey)
//        refreshToken = UserDefaults.standard.string(forKey: refreshTokenKey)
//    }
//
//    private func deleteTokensFromStorage() {
//        UserDefaults.standard.removeObject(forKey: accessTokenKey)
//        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
//    }
//}
//
//// MARK: - Models (Supabase Auth JSON)
//
//struct SupabaseSession: Codable {
//    let access_token: String
//    let refresh_token: String
//    let token_type: String?
//    let expires_in: Int?
//    let user: SupabaseUser?
//}
//
//struct SupabaseUser: Codable {
//    let id: String?
//    let email: String?
//    let user_metadata: UserMetadata?
//}
//
//struct UserMetadata: Codable {
//    let name: String?
//}
//
//struct SupabaseError: Codable {
//    let error: String?
//    let error_description: String?
//    let msg: String?
//}
//
//
//// MARK: - Kroger Items
//
//struct KrogerItem: Codable, Identifiable {
//    let productId: Int
//    let name: String
//    let brand: String?
//    let price: String?        // "1.49;1.49;2.49" — index-aligned with store_ids
//    let classifier: String?
//    let categories: String?
//    let image_url: String?
//    let size: String?
//    let search_keyword: String?
//    let store_ids: String?
//
//    var id: Int { productId }
//
//    var priceList: [Double] {
//        guard let price else { return [] }
//        return price.split(separator: ";")
//            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
//    }
//
//    var storeIdList: [String] {
//        guard let store_ids else { return [] }
//        return store_ids.split(separator: ";")
//            .map { $0.trimmingCharacters(in: .whitespaces) }
//    }
//
//    var minPrice: Double? {
//        priceList.filter { $0 > 0 }.min()
//    }
//
//    func price(forStoreId storeId: String) -> Double? {
//        guard let index = storeIdList.firstIndex(of: storeId),
//              index < priceList.count else { return nil }
//        return priceList[index]
//    }
//
//    func displayPrice(forStoreId storeId: String? = nil) -> String {
//        let p: Double?
//        if let storeId {
//            p = price(forStoreId: storeId) ?? minPrice
//        } else {
//            p = minPrice
//        }
//        guard let p else { return "Price N/A" }
//        return String(format: "$%.2f", p)
//    }
//
//    var imageURL: URL? {
//        guard let img = image_url, !img.isEmpty else { return nil }
//        return URL(string: img)
//    }
//}
//
//extension AuthManager {
//    func fetchKrogerItems(
//        search: String? = nil,
//        classifier: String? = nil,
//        limit: Int = 50,
//        offset: Int = 0
//    ) async throws -> [KrogerItem] {
//        let base = supabaseURL
//            .appendingPathComponent("rest/v1")
//            .appendingPathComponent("kroger_ingredients2")
//
//        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
//        var q: [URLQueryItem] = [
//            URLQueryItem(
//                name: "select",
//                value: "productId,name,brand,price,classifier,categories,image_url,size,search_keyword,store_ids"
//            ),
//            URLQueryItem(name: "limit",  value: "\(limit)"),
//            URLQueryItem(name: "offset", value: "\(offset)"),
//            URLQueryItem(name: "order",  value: "productId.asc"),
//        ]
//
//        if let s = search?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
//            q.append(URLQueryItem(
//                name: "or",
//                value: "(name.ilike.*\(s)*,search_keyword.ilike.*\(s)*)"
//            ))
//        }
//
//        if let cls = classifier, !cls.isEmpty {
//            q.append(URLQueryItem(name: "classifier", value: "eq.\(cls)"))
//        }
//
//        comps.queryItems = q
//        guard let url = comps.url else { throw URLError(.badURL) }
//
//        let (data, _) = try await request(
//            url: url,
//            method: "GET",
//            jsonBody: Optional<String>.none,
//            bearerToken: accessToken
//        )
//
//        do {
//            return try JSONDecoder().decode([KrogerItem].self, from: data)
//        } catch {
//            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
//            print("❌ KrogerItem decode error: \(error)")
//            print("❌ Raw JSON: \(raw.prefix(500))")
//            throw error
//        }
//    }
//}
//
////Onboard survey fetch/save
//struct UserPreferencesRow: Codable {
//    let user_id: String
//    let diet_preferences: [String]
//    let allergies: [String]
//}
//
//struct UserPreferencesUpsertBody: Codable {
//    let user_id: String
//    let diet_preferences: [String]
//    let allergies: [String]
//}
//
//extension AuthManager {
//    func fetchUserPreferences() async throws -> UserPreferences? {
//        guard let token = accessToken, let uid = userID else {
//            throw URLError(.userAuthenticationRequired)
//        }
//
//        let base = supabaseURL
//            .appendingPathComponent("rest/v1")
//            .appendingPathComponent("user_preferences")
//
//        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
//        comps.queryItems = [
//            URLQueryItem(name: "select", value: "user_id,diet_preferences,allergies"),
//            URLQueryItem(name: "user_id", value: "eq.\(uid)"),
//            URLQueryItem(name: "limit", value: "1")
//        ]
//
//        guard let url = comps.url else { throw URLError(.badURL) }
//
//        let (data, _) = try await request(
//            url: url,
//            method: "GET",
//            jsonBody: Optional<String>.none,
//            bearerToken: token
//        )
//
//        let rows = try JSONDecoder().decode([UserPreferencesRow].self, from: data)
//        guard let row = rows.first else { return nil }
//
//        return UserPreferences(
//            dietPreferences: row.diet_preferences,
//            allergies: row.allergies
//        )
//    }
//
//    func saveUserPreferences(_ preferences: UserPreferences) async throws {
//        guard let token = accessToken, let uid = userID else {
//            throw URLError(.userAuthenticationRequired)
//        }
//
//        let base = supabaseURL
//            .appendingPathComponent("rest/v1")
//            .appendingPathComponent("user_preferences")
//
//        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
//        comps.queryItems = [
//            URLQueryItem(name: "on_conflict", value: "user_id")
//        ]
//
//        guard let url = comps.url else { throw URLError(.badURL) }
//
//        let body = UserPreferencesUpsertBody(
//            user_id: uid,
//            diet_preferences: preferences.dietPreferences,
//            allergies: preferences.allergies
//        )
//
//        _ = try await request(
//            url: url,
//            method: "POST",
//            jsonBody: body,
//            bearerToken: token,
//            extraHeaders: [
//                "Prefer": "resolution=merge-duplicates,return=representation"
//            ]
//        )
//    }
//}
//
//// --- Recpie Fetcher --- //
//
//extension AuthManager {
//    func fetchRecipes(search: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> [RecipeRow] {
//        let base = supabaseURL
//            .appendingPathComponent("rest/v1/Recipes_Kaggle")
//
//        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
//        var queryItems: [URLQueryItem] = [
//            URLQueryItem(
//                name: "select",
//                value: "id,Title,Ingredients,Instructions,Image_Name,Cleaned_Ingredients,image_url"
//            ),
//            URLQueryItem(name: "limit", value: "\(limit)"),
//            URLQueryItem(name: "offset", value: "\(offset)"),
//            URLQueryItem(name: "order", value: "id.asc")
//        ]
//
//        if let s = search?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
//            queryItems.append(URLQueryItem(name: "Title", value: "ilike.*\(s)*"))
//        }
//
//        comps.queryItems = queryItems
//
//        let (data, _) = try await request(
//            url: comps.url!,
//            method: "GET",
//            jsonBody: Optional<String>.none,
//            bearerToken: accessToken
//        )
//
//        return try JSONDecoder().decode([RecipeRow].self, from: data)
//    }
//}
//
//
//// MARK: - Recipe Matches
//
//struct RecipeMatch: Codable, Identifiable {
//    let id: Int
//    let recipe_id: Int
//    let raw_ingredient: String
//    let matched_name: String?
//    let matched_product_id: String?
//    let matched_image: String?
//    let matched_size: String?
//    let min_price: Double?
//    let price_raw: String?
//    let store_ids: String?
//    let score: Double?
//    let confidence: String?
//    let match_rank: Int?
//
//    var displayPrice: String {
//        guard let p = min_price else { return "Price N/A" }
//        return String(format: "$%.2f", p)
//    }
//
//    var imageURL: URL? {
//        guard let img = matched_image, !img.isEmpty else { return nil }
//        return URL(string: img)
//    }
//}
//
//extension AuthManager {
//    func fetchRecipeMatches(recipeId: Int) async throws -> [RecipeMatch] {
//        let base = supabaseURL
//            .appendingPathComponent("rest/v1")
//            .appendingPathComponent("recipe_matches")
//
//        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
//        comps.queryItems = [
//            URLQueryItem(name: "select", value: "id,recipe_id,raw_ingredient,matched_name,matched_product_id,matched_image,matched_size,min_price,price_raw,store_ids,score,confidence,match_rank"),
//            URLQueryItem(name: "recipe_id",   value: "eq.\(recipeId)"),
//            URLQueryItem(name: "match_rank",  value: "not.is.null"),
//            URLQueryItem(name: "order",       value: "raw_ingredient.asc,match_rank.asc"),
//        ]
//
//        guard let url = comps.url else { throw URLError(.badURL) }
//
//        let (data, _) = try await request(
//            url: url, method: "GET",
//            jsonBody: Optional<String>.none,
//            bearerToken: accessToken
//        )
//
//        do {
//            return try JSONDecoder().decode([RecipeMatch].self, from: data)
//        } catch {
//            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
//            print("❌ RecipeMatch decode error: \(error)")
//            print("❌ Raw: \(raw.prefix(300))")
//            throw error
//        }
//    }
//}
//
//// MARK: - Kroger Store Locations
//
//struct KrogerStore: Codable, Identifiable {
//    let locationId: Int
//    let name: String?
//    let chain: String?
//    let address_line1: String?
//    let address_city: String?
//    let address_state: String?
//    let address_zipCode: Int?
//    let geo_latitude: Double?
//    let geo_longitude: Double?
//
//    var id: Int { locationId }
//
//    var displayName: String { name ?? "Kroger Store" }
//
//    var displayAddress: String {
//        [address_line1, address_city, address_state]
//            .compactMap { $0 }.filter { !$0.isEmpty }
//            .joined(separator: ", ")
//    }
//
//    var coordinate: CLLocationCoordinate2D? {
//        guard let lat = geo_latitude, let lng = geo_longitude else { return nil }
//        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
//    }
//
//    func distanceMiles(from coord: CLLocationCoordinate2D) -> Double? {
//        guard let c = coordinate else { return nil }
//        let loc1 = CLLocation(latitude: c.latitude, longitude: c.longitude)
//        let loc2 = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
//        return loc1.distance(from: loc2) / 1609.34
//    }
//}
//
//extension AuthManager {
//    func fetchNearbyKrogerStores(
//        near coordinate: CLLocationCoordinate2D,
//        radiusDegrees: Double = 0.2
//    ) async throws -> [KrogerStore] {
//        let base = supabaseURL
//            .appendingPathComponent("rest/v1")
//            .appendingPathComponent("kroger_locations")
//
//        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
//        comps.queryItems = [
//            URLQueryItem(name: "select", value: "locationId,name,chain,address_line1,address_city,address_state,address_zipCode,geo_latitude,geo_longitude"),
//            URLQueryItem(name: "geo_latitude",  value: "gte.\(coordinate.latitude  - radiusDegrees)"),
//            URLQueryItem(name: "geo_latitude",  value: "lte.\(coordinate.latitude  + radiusDegrees)"),
//            URLQueryItem(name: "geo_longitude", value: "gte.\(coordinate.longitude - radiusDegrees)"),
//            URLQueryItem(name: "geo_longitude", value: "lte.\(coordinate.longitude + radiusDegrees)"),
//            URLQueryItem(name: "limit", value: "50"),
//        ]
//
//        guard let url = comps.url else { throw URLError(.badURL) }
//
//        let (data, _) = try await request(
//            url: url, method: "GET",
//            jsonBody: Optional<String>.none,
//            bearerToken: accessToken
//        )
//
//        let stores = try JSONDecoder().decode([KrogerStore].self, from: data)
//        return stores
//            .filter { $0.coordinate != nil }
//            .sorted { (a: KrogerStore, b: KrogerStore) -> Bool in
//                (a.distanceMiles(from: coordinate) ?? 999) <
//                (b.distanceMiles(from: coordinate) ?? 999)
//            }
//    }
//}
//
//// MARK: - Scraped Ingredients (multi-store price comparison)
//
//struct ScrapedIngredient: Codable, Identifiable {
//    let id: String
//    let taxonomy: String
//    let store: String
//    let name: String
//    let price: Double?
//    let price_raw: String?
//    let price_unit: String?
//    let quantity: String?
//    let image_url: String?
//    let description: String?
//    let out_of_stock: Bool?
//
//    var displayPrice: String {
//        guard let p = price else { return "Price N/A" }
//        return String(format: "$%.2f", p)
//    }
//
//    var imageURL: URL? {
//        guard let img = image_url, !img.isEmpty else { return nil }
//        return URL(string: img)
//    }
//
//    var isAvailable: Bool { !(out_of_stock ?? false) }
//}
//
//extension AuthManager {
//
//    /// All store prices for a single taxonomy term, sorted cheapest first.
//    /// e.g. taxonomy = "Butter" → Walmart $2.97, Food4Less $3.29, Ralphs $3.49 ...
//    func fetchPricesForIngredient(taxonomy: String) async throws -> [ScrapedIngredient] {
//        let base = supabaseURL
//            .appendingPathComponent("rest/v1")
//            .appendingPathComponent("scraped_ingredients")
//
//        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
//        comps.queryItems = [
//            URLQueryItem(name: "select",   value: "id,taxonomy,store,name,price,price_raw,price_unit,quantity,image_url,out_of_stock"),
//            URLQueryItem(name: "taxonomy", value: "eq.\(taxonomy)"),
//            URLQueryItem(name: "order",    value: "price.asc.nullslast"),
//            URLQueryItem(name: "limit",    value: "50"),
//        ]
//
//        guard let url = comps.url else { throw URLError(.badURL) }
//
//        let (data, _) = try await request(
//            url: url, method: "GET",
//            jsonBody: Optional<String>.none,
//            bearerToken: accessToken
//        )
//        return try JSONDecoder().decode([ScrapedIngredient].self, from: data)
//    }
//
//    /// Search scraped ingredients by name or taxonomy across all stores.
//    /// Pass store: to filter to a single store.
//    func searchScrapedIngredients(
//        query: String,
//        store: String? = nil,
//        limit: Int = 50,
//        offset: Int = 0
//    ) async throws -> [ScrapedIngredient] {
//        let base = supabaseURL
//            .appendingPathComponent("rest/v1")
//            .appendingPathComponent("scraped_ingredients")
//
//        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
//        var q: [URLQueryItem] = [
//            URLQueryItem(name: "select", value: "id,taxonomy,store,name,price,price_raw,price_unit,quantity,image_url,out_of_stock"),
//            URLQueryItem(name: "order",  value: "price.asc.nullslast"),
//            URLQueryItem(name: "limit",  value: "\(limit)"),
//            URLQueryItem(name: "offset", value: "\(offset)"),
//        ]
//
//        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
//        if !trimmed.isEmpty {
//            q.append(URLQueryItem(name: "or",
//                value: "(name.ilike.*\(trimmed)*,taxonomy.ilike.*\(trimmed)*)"))
//        }
//
//        if let store {
//            q.append(URLQueryItem(name: "store", value: "eq.\(store)"))
//        }
//
//        comps.queryItems = q
//        guard let url = comps.url else { throw URLError(.badURL) }
//
//        let (data, _) = try await request(
//            url: url, method: "GET",
//            jsonBody: Optional<String>.none,
//            bearerToken: accessToken
//        )
//
//        do {
//            return try JSONDecoder().decode([ScrapedIngredient].self, from: data)
//        } catch {
//            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
//            print("❌ ScrapedIngredient decode error: \(error)")
//            print("❌ Raw: \(raw.prefix(300))")
//            throw error
//        }
//    }
//}
//
//// MARK: - Account Management
//
//extension AuthManager {
//
//    /// Change the current user's password.
//    func changePassword(to newPassword: String) async throws {
//        guard let token = accessToken else {
//            throw URLError(.userAuthenticationRequired)
//        }
//        let url = supabaseURL.appendingPathComponent("auth/v1/user")
//        let (data, _) = try await request(
//            url: url,
//            method: "PUT",
//            jsonBody: ["password": newPassword],
//            bearerToken: token
//        )
//        if let session = try? JSONDecoder().decode(SupabaseSession.self, from: data) {
//            applySession(session)
//        }
//    }
//
//    /// Permanently delete the current user's account.
//    /// Uses the admin endpoint which requires the service role key.
//    func deleteAccount() async throws {
//        guard let uid = userID else {
//            throw URLError(.userAuthenticationRequired)
//        }
//
//        // Step 1: delete user data from public tables
//        if let token = accessToken {
//            try? await deleteUserData(uid: uid, token: token)
//        }
//
//        // Step 2: delete the auth account via admin endpoint
//        // /auth/v1/admin/users/{uid} requires service role key
//        let url = supabaseURL
//            .appendingPathComponent("auth/v1/admin/users")
//            .appendingPathComponent(uid)
//
//        var req = URLRequest(url: url)
//        req.httpMethod = "DELETE"
//        req.setValue(serviceRoleKey, forHTTPHeaderField: "apikey")
//        req.setValue("Bearer \(serviceRoleKey)", forHTTPHeaderField: "Authorization")
//        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
//
//        let (data, resp) = try await URLSession.shared.data(for: req)
//        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
//
//        if !(200...299).contains(http.statusCode) {
//            let raw = String(data: data, encoding: .utf8) ?? ""
//            throw NSError(domain: "Supabase", code: http.statusCode,
//                          userInfo: [NSLocalizedDescriptionKey: "Delete failed: \(raw)"])
//        }
//
//        clearSession()
//    }
//
//    private func deleteUserData(uid: String, token: String) async throws {
//        let base = supabaseURL
//            .appendingPathComponent("rest/v1/user_preferences")
//        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
//        comps.queryItems = [URLQueryItem(name: "user_id", value: "eq.\(uid)")]
//        guard let url = comps.url else { return }
//        _ = try await request(
//            url: url,
//            method: "DELETE",
//            jsonBody: nil as [String: String]?,
//            bearerToken: token
//        )
//    }
//}

import Foundation
import CoreLocation
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
    @Published var userID: String? = nil
    @Published var userName: String? = nil
 
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
            self.userID = session.user?.id
            self.userName = session.user?.user_metadata?.name
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
                self.userID = session.user?.id
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
            self.userID = user.id
            self.userName = user.user_metadata?.name
        } catch {
            // token might be expired -> try refresh
            if let refreshed = try? await refreshSession() {
                self.userEmail = refreshed.user?.email
                self.isSignedIn = true
                self.userID = refreshed.user?.id
                self.userName = refreshed.user?.user_metadata?.name
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
        self.userID = session.user?.id
        self.userName = session.user?.user_metadata?.name
        saveTokensToStorage()
        self.isSignedIn = true
    }
 
    private func clearSession() {
        self.accessToken = nil
        self.refreshToken = nil
        self.userEmail = nil
        self.userID = nil
        self.userName = nil
        self.isSignedIn = false
        deleteTokensFromStorage()
    }
 
    private func request<T: Encodable>(
        url: URL,
        method: String,
        jsonBody: T?,
        bearerToken: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
 
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
 
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
 
        for (key, value) in extraHeaders {
            req.setValue(value, forHTTPHeaderField: key)
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
    let user_metadata: UserMetadata?
}
 
struct UserMetadata: Codable {
    let name: String?
}
 
struct SupabaseError: Codable {
    let error: String?
    let error_description: String?
    let msg: String?
}
 
 
// MARK: - Kroger Items
 
struct KrogerItem: Codable, Identifiable {
    let productId: Int
    let name: String
    let brand: String?
    let price: String?        // "1.49;1.49;2.49" — index-aligned with store_ids
    let classifier: String?
    let categories: String?
    let image_url: String?
    let size: String?
    let search_keyword: String?
    let store_ids: String?
 
    var id: Int { productId }
 
    var priceList: [Double] {
        guard let price else { return [] }
        return price.split(separator: ";")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
 
    var storeIdList: [String] {
        guard let store_ids else { return [] }
        return store_ids.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
 
    var minPrice: Double? {
        priceList.filter { $0 > 0 }.min()
    }
 
    func price(forStoreId storeId: String) -> Double? {
        guard let index = storeIdList.firstIndex(of: storeId),
              index < priceList.count else { return nil }
        return priceList[index]
    }
 
    func displayPrice(forStoreId storeId: String? = nil) -> String {
        let p: Double?
        if let storeId {
            p = price(forStoreId: storeId) ?? minPrice
        } else {
            p = minPrice
        }
        guard let p else { return "Price N/A" }
        return String(format: "$%.2f", p)
    }
 
    var imageURL: URL? {
        guard let img = image_url, !img.isEmpty else { return nil }
        return URL(string: img)
    }
}
 
extension AuthManager {
    func fetchKrogerItems(
        search: String? = nil,
        classifier: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [KrogerItem] {
        let base = supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent("kroger_ingredients2")
 
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [
            URLQueryItem(
                name: "select",
                value: "productId,name,brand,price,classifier,categories,image_url,size,search_keyword,store_ids"
            ),
            URLQueryItem(name: "limit",  value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "order",  value: "productId.asc"),
        ]
 
        if let s = search?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            q.append(URLQueryItem(
                name: "or",
                value: "(name.ilike.*\(s)*,search_keyword.ilike.*\(s)*)"
            ))
        }
 
        if let cls = classifier, !cls.isEmpty {
            q.append(URLQueryItem(name: "classifier", value: "eq.\(cls)"))
        }
 
        comps.queryItems = q
        guard let url = comps.url else { throw URLError(.badURL) }
 
        let (data, _) = try await request(
            url: url,
            method: "GET",
            jsonBody: Optional<String>.none,
            bearerToken: accessToken
        )
 
        do {
            return try JSONDecoder().decode([KrogerItem].self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ KrogerItem decode error: \(error)")
            print("❌ Raw JSON: \(raw.prefix(500))")
            throw error
        }
    }
}
 
//Onboard survey fetch/save
struct UserPreferencesRow: Codable {
    let user_id: String
    let diet_preferences: [String]
    let allergies: [String]
}
 
struct UserPreferencesUpsertBody: Codable {
    let user_id: String
    let diet_preferences: [String]
    let allergies: [String]
}
 
extension AuthManager {
    func fetchUserPreferences() async throws -> UserPreferences? {
        guard let token = accessToken, let uid = userID else {
            throw URLError(.userAuthenticationRequired)
        }
 
        let base = supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent("user_preferences")
 
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "select", value: "user_id,diet_preferences,allergies"),
            URLQueryItem(name: "user_id", value: "eq.\(uid)"),
            URLQueryItem(name: "limit", value: "1")
        ]
 
        guard let url = comps.url else { throw URLError(.badURL) }
 
        let (data, _) = try await request(
            url: url,
            method: "GET",
            jsonBody: Optional<String>.none,
            bearerToken: token
        )
 
        let rows = try JSONDecoder().decode([UserPreferencesRow].self, from: data)
        guard let row = rows.first else { return nil }
 
        return UserPreferences(
            dietPreferences: row.diet_preferences,
            allergies: row.allergies
        )
    }
 
    func saveUserPreferences(_ preferences: UserPreferences) async throws {
        guard let token = accessToken, let uid = userID else {
            throw URLError(.userAuthenticationRequired)
        }
 
        let base = supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent("user_preferences")
 
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "on_conflict", value: "user_id")
        ]
 
        guard let url = comps.url else { throw URLError(.badURL) }
 
        let body = UserPreferencesUpsertBody(
            user_id: uid,
            diet_preferences: preferences.dietPreferences,
            allergies: preferences.allergies
        )
 
        _ = try await request(
            url: url,
            method: "POST",
            jsonBody: body,
            bearerToken: token,
            extraHeaders: [
                "Prefer": "resolution=merge-duplicates,return=representation"
            ]
        )
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
 
 
// MARK: - Recipe Matches
 
struct RecipeMatch: Codable, Identifiable {
    let id: Int
    let recipe_id: Int
    let raw_ingredient: String
    let matched_name: String?
    let matched_product_id: String?
    let matched_image: String?
    let matched_size: String?
    let min_price: Double?
    let price_raw: String?
    let store_ids: String?
    let score: Double?
    let confidence: String?
    let match_rank: Int?
 
    var displayPrice: String {
        guard let p = min_price else { return "Price N/A" }
        return String(format: "$%.2f", p)
    }
 
    var imageURL: URL? {
        guard let img = matched_image, !img.isEmpty else { return nil }
        return URL(string: img)
    }
}
 
extension AuthManager {
    func fetchRecipeMatches(recipeId: Int) async throws -> [RecipeMatch] {
        let base = supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent("recipe_matches")
 
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,recipe_id,raw_ingredient,matched_name,matched_product_id,matched_image,matched_size,min_price,price_raw,store_ids,score,confidence,match_rank"),
            URLQueryItem(name: "recipe_id",   value: "eq.\(recipeId)"),
            URLQueryItem(name: "match_rank",  value: "not.is.null"),
            URLQueryItem(name: "order",       value: "raw_ingredient.asc,match_rank.asc"),
        ]
 
        guard let url = comps.url else { throw URLError(.badURL) }
 
        let (data, _) = try await request(
            url: url, method: "GET",
            jsonBody: Optional<String>.none,
            bearerToken: accessToken
        )
 
        do {
            return try JSONDecoder().decode([RecipeMatch].self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ RecipeMatch decode error: \(error)")
            print("❌ Raw: \(raw.prefix(300))")
            throw error
        }
    }
}
 
// MARK: - Kroger Store Locations
 
struct KrogerStore: Codable, Identifiable {
    let locationId: Int
    let name: String?
    let chain: String?
    let address_line1: String?
    let address_city: String?
    let address_state: String?
    let address_zipCode: Int?
    let geo_latitude: Double?
    let geo_longitude: Double?
 
    var id: Int { locationId }
 
    var displayName: String { name ?? "Kroger Store" }
 
    var displayAddress: String {
        [address_line1, address_city, address_state]
            .compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
 
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = geo_latitude, let lng = geo_longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
 
    func distanceMiles(from coord: CLLocationCoordinate2D) -> Double? {
        guard let c = coordinate else { return nil }
        let loc1 = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let loc2 = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return loc1.distance(from: loc2) / 1609.34
    }
}
 
extension AuthManager {
    func fetchNearbyKrogerStores(
        near coordinate: CLLocationCoordinate2D,
        radiusDegrees: Double = 0.2
    ) async throws -> [KrogerStore] {
        let base = supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent("kroger_locations")
 
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "select", value: "locationId,name,chain,address_line1,address_city,address_state,address_zipCode,geo_latitude,geo_longitude"),
            URLQueryItem(name: "geo_latitude",  value: "gte.\(coordinate.latitude  - radiusDegrees)"),
            URLQueryItem(name: "geo_latitude",  value: "lte.\(coordinate.latitude  + radiusDegrees)"),
            URLQueryItem(name: "geo_longitude", value: "gte.\(coordinate.longitude - radiusDegrees)"),
            URLQueryItem(name: "geo_longitude", value: "lte.\(coordinate.longitude + radiusDegrees)"),
            URLQueryItem(name: "limit", value: "50"),
        ]
 
        guard let url = comps.url else { throw URLError(.badURL) }
 
        let (data, _) = try await request(
            url: url, method: "GET",
            jsonBody: Optional<String>.none,
            bearerToken: accessToken
        )
 
        let stores = try JSONDecoder().decode([KrogerStore].self, from: data)
        return stores
            .filter { $0.coordinate != nil }
            .sorted { (a: KrogerStore, b: KrogerStore) -> Bool in
                (a.distanceMiles(from: coordinate) ?? 999) <
                (b.distanceMiles(from: coordinate) ?? 999)
            }
    }
}
 
// MARK: - Scraped Ingredients (multi-store price comparison)
 
struct ScrapedIngredient: Codable, Identifiable {
    let id: String
    let taxonomy: String
    let store: String
    let name: String
    let price: Double?
    let price_raw: String?
    let price_unit: String?
    let quantity: String?
    let image_url: String?
    let description: String?
    let out_of_stock: Bool?
 
    var displayPrice: String {
        guard let p = price else { return "Price N/A" }
        return String(format: "$%.2f", p)
    }
 
    var imageURL: URL? {
        guard let img = image_url, !img.isEmpty else { return nil }
        return URL(string: img)
    }
 
    var isAvailable: Bool { !(out_of_stock ?? false) }
}
 
extension AuthManager {
 
    /// All store prices for a single taxonomy term, sorted cheapest first.
    /// e.g. taxonomy = "Butter" → Walmart $2.97, Food4Less $3.29, Ralphs $3.49 ...
    func fetchPricesForIngredient(taxonomy: String) async throws -> [ScrapedIngredient] {
        let base = supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent("scraped_ingredients")
 
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "select",   value: "id,taxonomy,store,name,price,price_raw,price_unit,quantity,image_url,out_of_stock"),
            URLQueryItem(name: "taxonomy", value: "eq.\(taxonomy)"),
            URLQueryItem(name: "order",    value: "price.asc.nullslast"),
            URLQueryItem(name: "limit",    value: "50"),
        ]
 
        guard let url = comps.url else { throw URLError(.badURL) }
 
        let (data, _) = try await request(
            url: url, method: "GET",
            jsonBody: Optional<String>.none,
            bearerToken: accessToken
        )
        return try JSONDecoder().decode([ScrapedIngredient].self, from: data)
    }
 
    /// Search scraped ingredients by name or taxonomy across all stores.
    /// Pass store: to filter to a single store.
    func searchScrapedIngredients(
        query: String,
        store: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [ScrapedIngredient] {
        let base = supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent("scraped_ingredients")
 
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,taxonomy,store,name,price,price_raw,price_unit,quantity,image_url,out_of_stock"),
            URLQueryItem(name: "order",  value: "price.asc.nullslast"),
            URLQueryItem(name: "limit",  value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
        ]
 
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            q.append(URLQueryItem(name: "or",
                value: "(name.ilike.*\(trimmed)*,taxonomy.ilike.*\(trimmed)*)"))
        }
 
        if let store {
            q.append(URLQueryItem(name: "store", value: "eq.\(store)"))
        }
 
        comps.queryItems = q
        guard let url = comps.url else { throw URLError(.badURL) }
 
        let (data, _) = try await request(
            url: url, method: "GET",
            jsonBody: Optional<String>.none,
            bearerToken: accessToken
        )
 
        do {
            return try JSONDecoder().decode([ScrapedIngredient].self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ ScrapedIngredient decode error: \(error)")
            print("❌ Raw: \(raw.prefix(300))")
            throw error
        }
    }
}
 
// MARK: - Account Management
 
extension AuthManager {
 
    /// Change the current user's password.
    func changePassword(to newPassword: String) async throws {
        guard let token = accessToken else {
            throw URLError(.userAuthenticationRequired)
        }
        let url = supabaseURL.appendingPathComponent("auth/v1/user")
        let (data, _) = try await request(
            url: url,
            method: "PUT",
            jsonBody: ["password": newPassword],
            bearerToken: token
        )
        if let session = try? JSONDecoder().decode(SupabaseSession.self, from: data) {
            applySession(session)
        }
    }
 
    /// Permanently delete the current user's account.
    /// Uses the admin endpoint which requires the service role key.
    func deleteAccount() async throws {
        guard let uid = userID else {
            throw URLError(.userAuthenticationRequired)
        }
 
        // Step 1: delete user data from public tables
        if let token = accessToken {
            try? await deleteUserData(uid: uid, token: token)
        }
 
        // Step 2: delete the auth account via admin endpoint
        // /auth/v1/admin/users/{uid} requires service role key
        let url = supabaseURL
            .appendingPathComponent("auth/v1/admin/users")
            .appendingPathComponent(uid)
 
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
//        req.setValue(serviceRoleKey, forHTTPHeaderField: "apikey")
//        req.setValue("Bearer \(serviceRoleKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
 
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
 
        if !(200...299).contains(http.statusCode) {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Supabase", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Delete failed: \(raw)"])
        }
 
        clearSession()
    }
 
    private func deleteUserData(uid: String, token: String) async throws {
        let base = supabaseURL
            .appendingPathComponent("rest/v1/user_preferences")
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "user_id", value: "eq.\(uid)")]
        guard let url = comps.url else { return }
        _ = try await request(
            url: url,
            method: "DELETE",
            jsonBody: nil as [String: String]?,
            bearerToken: token
        )
    }
}
 
// MARK: - Scraped Recipe Matches (multi-store)
 
struct ScrapedRecipeMatch: Codable, Identifiable {
    let id: Int
    let recipe_id: Int
    let recipe_title: String?
    let raw_ingredient: String
    let matched_name: String?
    let matched_product_id: String?
    let matched_store: String?
    let matched_image: String?
    let matched_size: String?
    let min_price: Double?
    let score: Double?
    let confidence: String?
    let match_rank: Int?
 
    var displayPrice: String {
        guard let p = min_price else { return "Price N/A" }
        return String(format: "$%.2f", p)
    }
 
    var imageURL: URL? {
        guard let img = matched_image, !img.isEmpty else { return nil }
        return URL(string: img)
    }
}
 
extension AuthManager {
    func fetchScrapedRecipeMatches(recipeId: Int) async throws -> [ScrapedRecipeMatch] {
        let base = supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent("scraped_recipe_matches")
 
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "select",     value: "id,recipe_id,recipe_title,raw_ingredient,matched_name,matched_product_id,matched_store,matched_image,matched_size,min_price,score,confidence,match_rank"),
            URLQueryItem(name: "recipe_id",  value: "eq.\(recipeId)"),
            URLQueryItem(name: "match_rank", value: "not.is.null"),
            URLQueryItem(name: "order",      value: "raw_ingredient.asc,match_rank.asc"),
        ]
 
        guard let url = comps.url else { throw URLError(.badURL) }
 
        let (data, _) = try await request(
            url: url, method: "GET",
            jsonBody: Optional<String>.none,
            bearerToken: accessToken
        )
 
        do {
            return try JSONDecoder().decode([ScrapedRecipeMatch].self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ ScrapedRecipeMatch decode error: \(error)")
            print("❌ Raw: \(raw.prefix(300))")
            throw error
        }
    }
}
