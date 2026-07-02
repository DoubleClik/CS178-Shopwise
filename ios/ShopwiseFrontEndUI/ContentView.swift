//
//  ContentView.swift
//  ShopwiseFrontEndUI
//
//  Created by James Chang on 1/13/26.
//

import SwiftUI
import SwiftData

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
}

#Preview {
    AuthView()
        .environmentObject(AuthManager())
}

