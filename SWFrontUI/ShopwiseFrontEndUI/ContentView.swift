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
    var body: some View {
        List {
            Section("Preferences") {
                Text("Settings options will go here")
                    .foregroundStyle(.secondary)
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
                                    cartStore.add(name: item.name, unit: unitText(for: item) ?? "", price: item.retail_price ?? 0)
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
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.978194, longitude: -117.367861),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    
    private struct DroppedPin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }
    @State private var droppedPins: [DroppedPin] = []
    
    var body: some View {
        List {
            Section() {
                CardContainer {
                    MapReader { proxy in
                        Map(position: $position) {
                            ForEach(droppedPins) { pin in
                                Marker("Selected", coordinate: pin.coordinate)
                            }
                        }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture { point in
                            if let coord = proxy.convert(point, from: .local) {
                                droppedPins.append(DroppedPin(coordinate: coord))
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
            }

            Section("Nearby Grocery Stores") {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                    VStack(alignment: .leading) {
                        Text("Walmart Supercenter")
                        Text("2.5 mi")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "mappin.circle.fill")
                    VStack(alignment: .leading) {
                        Text("Ralph's")
                        Text("4.2 mi")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle("ShopWise")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    NavigationLink { ProfileView() } label: { Image(systemName: "person.crop.circle") }
                }
            }
        }
    }
}

struct CartView: View {
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
                                .buttonStyle(.borderless) // ✅

                                Text("\(item.quantity)")
                                    .font(.headline)
                                    .frame(minWidth: 24)

                                Button {
                                    cartStore.increment(item)
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                                .buttonStyle(.borderless) // ✅
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
                    // placeholder: checkout
                } label: {
                    Text("Checkout")
                        .frame(maxWidth: .infinity)
                }
                .disabled(cartStore.items.isEmpty)
            }
        }
        .navigationTitle("Cart")
        .appToolbar()
    }
}

struct Recipe: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let difficulty: String
    let minutes: Int
    let ingredients: [String]
}

struct RecipeView: View {
    @State private var query = ""
    @State private var expandedID: Recipe.ID? = nil   //which recipe is expanded

    private let recipes: [Recipe] = [
        Recipe(
            name: "Spaghetti",
            difficulty: "Easy",
            minutes: 25,
            ingredients: ["Spaghetti pasta", "Marinara sauce", "Garlic", "Onion", "Olive oil", "Parmesan"]
        ),
        Recipe(
            name: "Orange Chicken",
            difficulty: "Medium",
            minutes: 35,
            ingredients: ["Chicken breast", "Cornstarch", "Orange juice", "Soy sauce", "Honey", "Garlic", "Ginger", "Rice"]
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
                    //Tappable card that expands/collapses
                    Button {
                        withAnimation(.snappy) {
                            expandedID = (expandedID == recipe.id) ? nil : recipe.id
                        }
                    } label: {
                        CardContainer {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 54, height: 54)
                                    .overlay(
                                        Image(systemName: "fork.knife")
                                            .foregroundStyle(.secondary)
                                    )

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

                    // Dropdown ingredients(replace hardcoded data)
                    if expandedID == recipe.id {
                        CardContainer {
                            Text("Ingredients")
                                .font(.headline)

                            ForEach(recipe.ingredients, id: \.self) { item in
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.secondary)
                                    Text(item)
                                }
                                .padding(.vertical, 2)
                            }

                            Button {
                                // placeholder: add ingredients to cart
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
}


struct ContentView: View {
    @StateObject private var cartStore = CartStore()

    var body: some View {
        TabView {
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack { RecipeView() }
                .tabItem { Label("Recipe", systemImage: "book") }

            NavigationStack { MapView() }
                .tabItem { Label("Map", systemImage: "map") }

            NavigationStack { CartView() }
                .tabItem { Label("Cart", systemImage: "cart") }
                .when(cartStore.itemCount > 0) { view in
                    view.badge(cartStore.itemCount)
                }
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
