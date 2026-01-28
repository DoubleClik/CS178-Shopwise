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
    var body: some View {
        List {
            Section("Account") {
                Text("Profile info will go here")
                    .foregroundStyle(.secondary)
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
    @State private var query = ""
    @State private var selectedCategory: String = "All"

    private let categories = ["All", "Fruits", "Vegetables", "Dairy", "Bakery"]

    var body: some View {
        List {
            // Category row
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(categories, id: \.self) { cat in
                            CategoryChip(title: cat, isSelected: selectedCategory == cat) {
                                selectedCategory = cat
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Big product card placeholder (like the “milk/strawberries” card)
            Section {
                CardContainer {
                    HStack(spacing: 12) {
                        Image("strawberry")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 90, height: 90)   // <- change size here
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Organic Strawberries")
                                .font(.headline)

                            Text("1 lb")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("$3.99")
                                    .font(.headline)

                                Spacer()

                                Button {
                                    // placeholder: add to cart
                                } label: {
                                    Label("Add", systemImage: "cart.badge.plus")
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Image("cutiesorange")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 90, height: 90)   // <- change size here
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cuties Oranges")
                                .font(.headline)

                            Text("5 lb")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("$5.99")
                                    .font(.headline)

                                Spacer()

                                Button {
                                    // placeholder: add to cart
                                } label: {
                                    Label("Add", systemImage: "cart.badge.plus")
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }

        }
        .listStyle(.plain)
        .navigationTitle("ShopWise")
        .searchable(text: $query, prompt: "Search products…")
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


struct MapView: View {
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.978194, longitude: -117.367861),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    var body: some View {
        List {
            Section() {
                CardContainer {
                    Map(position: $position)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    var body: some View {
        List {
            Section("Items") {
                Text("Cart items will go here")
                    .foregroundStyle(.secondary)
            }

            Section("Summary") {
                HStack {
                    Text("Total")
                    Spacer()
                    Text("$0.00")
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
        .modelContainer(for: Item.self, inMemory: true)
}

