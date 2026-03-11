//
//  ContentView.swift
//  ShopwiseFrontEndUI
//
//  Created by James Chang on 1/13/26.
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation


struct AppToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }

                        NavigationLink {
                            ProfileView()
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
            }
    }
}

extension View {
    func appToolbar() -> some View {
        self.modifier(AppToolbar())
    }
}

extension View {
    @ViewBuilder
    func when(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        List {
            Section("Account") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text(auth.userEmail ?? "No email")
                            .font(.headline)

                        Text("Signed in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Preferences") {
                NavigationLink {
                    OnboardingSurveyView()
                } label: {
                    Label("Edit Diet & Allergies", systemImage: "slider.horizontal.3")
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Text("Sign Out")
                }
            }
        }
        .navigationTitle("Profile")
    }
}

struct SettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("locationEnabled") private var locationEnabled = true
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false

    var body: some View {
        List {
            Section("Preferences") {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                Toggle("Use Location Services", isOn: $locationEnabled)
                Toggle("Dark Mode", isOn: $darkModeEnabled)
            }

            Section("Support") {
                Button("Help Center") {
                    // placeholder
                }

                Button("About ShopWise") {
                    // placeholder
                }
            }

            Section("App Info") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}


struct SearchView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var cartStore: CartStore
    
    @State private var query = ""
    @State private var selectedFilter: String = "All"
    @State private var results: [WalmartItem] = []
    @State private var isLoading = false
    @State private var errorText: String? = nil

    @State private var pageSize = 50
    @State private var offset = 0

    @State private var isLoadingMore = false
    @State private var hasMore = true

    private let filters = ["All", "Ingredients", "Non-Ingredients"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // Title
                Text("ShopWise")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.top, 6)

                // Search bar (custom like your right screenshot)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search products...", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if !query.isEmpty {
                        Button {
                            query = ""
                            searchItems(reset: true)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                // Category chips row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filters, id: \.self) { f in
                            SearchCategoryChip(title: f, isSelected: selectedFilter == f) {
                                selectedFilter = f
                                searchItems(reset: true)   // ✅ ADD HERE
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                // Content
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading…")
                        Spacer()
                    }
                    .padding(.top, 24)
                } else if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .padding(.top, 10)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, item in
                            ProductCard(
                                imageURL: bestImageURL(for: item),
                                title: item.name,
                                unit: unitText(for: item),
                                priceText: formatPrice(item.retail_price),
                                onAdd: {
                                    cartStore.add(id: String(item.id), name: item.name, unit: unitText(for: item) ?? "", price: item.retail_price ?? 0)
                                }
                            )
                            .onAppear {
                                // When the LAST item appears, load more
                                if index == filteredResults.count - 1 {
                                    searchItems(reset: false)
                                }
                            }
                        }                    }
                    .padding(.top, 4)
                }
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .appToolbar() // <-- uses your existing Settings/Profile toolbar
        .onChange(of: query) { _, _ in
            searchItems(reset: true)
        }
        .task {
            searchItems(reset: true)
        }
    }

    // MARK: - Filtering
    private var filteredResults: [WalmartItem] {
        switch selectedFilter {
        case "Ingredients":
            return results.filter { $0.ingredient == true }
        case "Non-Ingredients":
            return results.filter { $0.ingredient == false }
        default:
            return results
        }
    }

    // MARK: - Helpers (image/price/unit)
    private func bestImageURL(for item: WalmartItem) -> URL? {
        if let s = item.thumbnailImage, let url = URL(string: s), !s.isEmpty { return url }
        if let s = item.mediumImage, let url = URL(string: s), !s.isEmpty { return url }
        if let s = item.largeImage, let url = URL(string: s), !s.isEmpty { return url }
        return nil
    }

    private func formatPrice(_ p: Double?) -> String {
        guard let p else { return "Price unavailable" }
        return String(format: "$%.2f", p)
    }

    private func unitText(for item: WalmartItem) -> String? {
        // Your Supabase data doesn't include a unit column.
        // If classifiers contains something unit-like, show it; otherwise hide.
        let cls = (item.classifiers ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if cls.isEmpty { return nil }
        return cls
    }

    // MARK: - Supabase fetch
    private func searchItems(reset: Bool = true) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // If we're already loading more, don't double-fire
        if isLoadingMore { return }

        if reset {
            offset = 0
            results = []
            hasMore = true
        } else {
            // if we already know there are no more rows, stop
            if !hasMore { return }
        }

        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorText = nil

        Task {
            do {
                let ingredientOnly: Bool? = {
                    switch selectedFilter {
                    case "Ingredients": return true
                    case "Non-Ingredients": return false
                    default: return nil
                    }
                }()

                let newItems = try await auth.fetchWalmartItems(
                    search: trimmed.isEmpty ? nil : trimmed,
                    ingredientOnly: ingredientOnly,   // ✅ NEW
                    limit: pageSize,
                    offset: offset
                )

                await MainActor.run {
                    // Append results
                    results.append(contentsOf: newItems)

                    // Move offset forward
                    offset += newItems.count

                    // If we got fewer than pageSize, we reached the end
                    if newItems.count < pageSize { hasMore = false }

                    isLoading = false
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    errorText = "Search failed: \(error.localizedDescription)"
                    isLoading = false
                    isLoadingMore = false
                }
            }
        }
    }
}


struct SearchCategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.18) : Color(.systemGray6))
                .foregroundStyle(isSelected ? Color.blue : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ProductCard: View {
    let imageURL: URL?
    let title: String
    let unit: String?
    let priceText: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 74, height: 74)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 74, height: 74)
                        .clipped()
                case .failure:
                    Image(systemName: "photo")
                        .frame(width: 74, height: 74)
                        .foregroundStyle(.secondary)
                @unknown default:
                    EmptyView()
                        .frame(width: 74, height: 74)
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(priceText)
                    .font(.headline)
            }

            Spacer()

            Button(action: onAdd) {
                HStack(spacing: 8) {
                    Image(systemName: "cart.badge.plus")
                    Text("Add")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(Color.blue)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(.systemGray6).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct MapView: View {
    @StateObject private var locationManager = LocationManager()

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.978194, longitude: -117.367861),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    @State private var stores: [StoreLocation] = [
        StoreLocation(
            id: "store_walmart",
            name: "Walmart Supercenter",
            latitude: 33.988194,
            longitude: -117.361861,
            address: nil,
            chain: "Walmart"
        ),
        StoreLocation(
            id: "store_ralphs",
            name: "Ralphs",
            latitude: 33.970194,
            longitude: -117.363861,
            address: nil,
            chain: "Ralphs"
        )
    ]

    var body: some View {
        List {
            Section {
                CardContainer {
                    Map(position: $position) {
                        UserAnnotation()

                        ForEach(stores) { store in
                            Marker(store.name, coordinate: store.coordinate)
                        }
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .listRowInsets(EdgeInsets())
            }

            Section("Nearby Grocery Stores") {
                ForEach(stores) { store in
                    Button {
                        position = .region(
                            MKCoordinateRegion(
                                center: store.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                            )
                        )
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill")

                            VStack(alignment: .leading) {
                                Text(store.name)
                                Text(store.chain ?? "Store")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Location") {
                Button {
                    centerOnUser()
                } label: {
                    Label("Center on Me", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(locationManager.userLocation == nil)

                HStack {
                    Text("Permission")
                    Spacer()
                    Text(locationStatusText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("ShopWise")
        .appToolbar()
        .onAppear {
            locationManager.requestPermission()
        }
        .onChange(of: locationManager.userLocation?.latitude ?? 0) { _, newLatitude in
            guard newLatitude != 0 else { return }
            centerOnUser()
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return "Not Requested"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways:
            return "Allowed"
        case .authorizedWhenInUse:
            return "Allowed"
        @unknown default:
            return "Unknown"
        }
    }

    private func centerOnUser() {
        guard let user = locationManager.userLocation else { return }

        position = .region(
            MKCoordinateRegion(
                center: user,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }
}

struct CartView: View {
    @State private var showShoppingList = false
    @EnvironmentObject private var cartStore: CartStore

    var body: some View {
        List {
            Section("Items") {
                if cartStore.items.isEmpty {
                    Text("Cart is empty")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cartStore.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                Text(item.unit)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "$%.2f", item.price))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 10) {
                                Button {
                                    cartStore.decrement(item)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)

                                Text("\(item.quantity)")
                                    .font(.headline)
                                    .frame(minWidth: 24)

                                Button {
                                    cartStore.increment(item)
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            cartStore.remove(cartStore.items[idx])
                        }
                    }
                }
            }

            Section("Summary") {
                HStack {
                    Text("Total")
                    Spacer()
                    Text(String(format: "$%.2f", cartStore.total))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    showShoppingList = true
                } label: {
                    Text("Checkout")
                        .frame(maxWidth: .infinity)
                }
                .disabled(cartStore.items.isEmpty)
            }
        }
        .navigationTitle("Cart")
        .appToolbar()
        .navigationDestination(isPresented: $showShoppingList) {
            ShoppingListView()
        }
    }
}

struct RecipeView: View {
    @State private var query = ""
    @State private var expandedID: String? = nil
    @State private var excludedByRecipe: [String: Set<String>] = [:]

    @EnvironmentObject private var cartStore: CartStore

    private let recipes: [Recipe] = [
        Recipe(
            id: "recipe_spaghetti",
            name: "Spaghetti",
            difficulty: "Easy",
            minutes: 25,
            imageURL: nil,
            imageName: "spaghetti",
            ingredients: [
                Ingredient(id: "ing_spaghetti", name: "Spaghetti pasta", unit: "1 lb", price: 2.49, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_marinara", name: "Marinara sauce", unit: "24 oz", price: 3.99, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_garlic", name: "Garlic", unit: "3 ct", price: 1.29, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_onion", name: "Onion", unit: "1 ct", price: 0.99, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_olive_oil", name: "Olive oil", unit: "16.9 oz", price: 6.49, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_parmesan", name: "Parmesan", unit: "6 oz", price: 4.49, imageURL: nil, imageName: nil)
            ]
        ),
        Recipe(
            id: "recipe_orange_chicken",
            name: "Orange Chicken",
            difficulty: "Medium",
            minutes: 35,
            imageURL: nil,
            imageName: "orangechicken",
            ingredients: [
                Ingredient(id: "ing_chicken_breast", name: "Chicken breast", unit: "1 lb", price: 5.99, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_cornstarch", name: "Cornstarch", unit: "16 oz", price: 1.99, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_orange_juice", name: "Orange juice", unit: "12 oz", price: 3.49, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_soy_sauce", name: "Soy sauce", unit: "10 oz", price: 2.29, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_honey", name: "Honey", unit: "12 oz", price: 4.79, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_garlic", name: "Garlic", unit: "3 ct", price: 1.29, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_ginger", name: "Ginger", unit: "3 oz", price: 1.49, imageURL: nil, imageName: nil),
                Ingredient(id: "ing_rice", name: "Rice", unit: "2 lb", price: 3.79, imageURL: nil, imageName: nil)
            ]
        )
    ]

    private var filtered: [Recipe] {
        if query.isEmpty { return recipes }
        return recipes.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            ForEach(filtered) { recipe in
                Section {
                    Button {
                        withAnimation(.snappy) {
                            expandedID = (expandedID == recipe.id) ? nil : recipe.id
                        }
                    } label: {
                        CardContainer {
                            HStack(spacing: 12) {
                                if let imageName = recipe.imageName {
                                    Image(imageName)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 54, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else {
                                    Circle()
                                        .fill(Color(.systemGray5))
                                        .frame(width: 54, height: 54)
                                        .overlay(
                                            Image(systemName: "fork.knife")
                                                .foregroundStyle(.secondary)
                                        )
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.name)
                                        .font(.headline)
                                    Text("\(recipe.difficulty) • \(recipe.minutes) min")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: expandedID == recipe.id ? "chevron.up" : "chevron.down")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if expandedID == recipe.id {
                        CardContainer {
                            if let imageName = recipe.imageName {
                                Image(imageName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 160)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            Text("Ingredients")
                                .font(.headline)

                            ForEach(recipe.ingredients) { ingredient in
                                let isExcluded = excludedByRecipe[recipe.id, default: []].contains(ingredient.id)

                                Button {
                                    if isExcluded {
                                        excludedByRecipe[recipe.id, default: []].remove(ingredient.id)
                                    } else {
                                        excludedByRecipe[recipe.id, default: []].insert(ingredient.id)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isExcluded ? "square" : "checkmark.square.fill")
                                            .imageScale(.large)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ingredient.name)
                                                .strikethrough(isExcluded)
                                            Text(ingredient.unit)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text(String(format: "$%.2f", ingredient.price))
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                addIngredientsToCart(recipe)
                            } label: {
                                Label("Add Ingredients to Cart", systemImage: "cart.badge.plus")
                                    .frame(maxWidth: .infinity)
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("ShopWise")
        .searchable(text: $query, prompt: "Search recipes…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    NavigationLink { ProfileView() } label: { Image(systemName: "person.crop.circle") }
                }
            }
        }
    }

    private func addIngredientsToCart(_ recipe: Recipe) {
        let excluded = excludedByRecipe[recipe.id, default: []]

        for ingredient in recipe.ingredients where !excluded.contains(ingredient.id) {
            cartStore.add(
                id: ingredient.id,
                name: ingredient.name,
                unit: ingredient.unit,
                price: ingredient.price
            )
        }
    }
}

struct ShoppingListView: View {
    @EnvironmentObject private var cartStore: CartStore
    @Environment(\.dismiss) private var dismiss

    @State private var checkedIDs: Set<String> = []

    private var checkedTotal: Double {
        cartStore.items
            .filter { checkedIDs.contains($0.id) }
            .reduce(0) { $0 + ($1.price * Double($1.quantity)) }
    }

    private var checkedCount: Int {
        cartStore.items.filter { checkedIDs.contains($0.id) }.count
    }

    var body: some View {
        List {
            Section("Shopping List") {
                if cartStore.items.isEmpty {
                    Text("No items to shop for.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cartStore.items) { item in
                        Button {
                            toggle(item.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: checkedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .imageScale(.large)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .strikethrough(checkedIDs.contains(item.id))
                                    Text("\(item.quantity) × \(item.unit)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(String(format: "$%.2f", item.price * Double(item.quantity)))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !cartStore.items.isEmpty {
                Section {
                    Button("Mark All") {
                        checkedIDs = Set(cartStore.items.map { $0.id })
                    }

                    Button("Clear Checks") {
                        checkedIDs.removeAll()
                    }

                    Button(role: .destructive) {
                        cartStore.clear()
                        checkedIDs.removeAll()
                        dismiss()
                    } label: {
                        Text("Clear Cart")
                    }
                }
            }
        }
        .navigationTitle("Shopping List")
        .appToolbar()
        .safeAreaInset(edge: .bottom) {
            if !cartStore.items.isEmpty {
                VStack(spacing: 0) {
                    Divider()

                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Checked: \(checkedCount)/\(cartStore.items.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Current Total")
                                    .font(.headline)
                            }

                            Spacer()

                            Text(String(format: "$%.2f", checkedTotal))
                                .font(.title3)
                                .monospacedDigit()
                        }

                        Button {
                            cartStore.clear()
                            checkedIDs.removeAll()
                            dismiss()
                        } label: {
                            Label("Finish Trip", systemImage: "checkmark.seal.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if checkedIDs.contains(id) {
            checkedIDs.remove(id)
        } else {
            checkedIDs.insert(id)
        }
    }
}

struct ContentView: View {
    @StateObject private var cartStore = CartStore()

    enum Tab: Hashable {
        case search, recipe, map, cart
    }

    @State private var selectedTab: Tab = .search

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            NavigationStack { RecipeView() }
                .tabItem { Label("Recipe", systemImage: "book") }
                .tag(Tab.recipe)

            NavigationStack { MapView() }
                .tabItem { Label("Map", systemImage: "map") }
                .tag(Tab.map)

            NavigationStack { CartView() }
                .tabItem { Label("Cart", systemImage: "cart") }
                .tag(Tab.cart)
                .badge(cartStore.itemCount)
        }
        .environmentObject(cartStore)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .modelContainer(for: Item.self, inMemory: true)
}

#Preview {
    AuthView()
        .environmentObject(AuthManager())
}

