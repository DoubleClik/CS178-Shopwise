//
//  ContentView.swift
//  ShopwiseFrontEndUI
//
//  Created by James Chang on 1/13/26.
//

import SwiftUI
import SwiftData
import MapKit
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

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        List {
            Section {
                Text("Search results will go here")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search store for items")
        .appToolbar()
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

struct MapView: View {
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.057, longitude: -117.821),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    var body: some View {
        List {
            Section("Nearby Stores") {
                // Mini map card
                Map(position: $position)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .listRowInsets(EdgeInsets()) // optional: makes it wider

                Text("Map preview goes here.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Map")
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


struct RecipeView: View {
    var body: some View {
        List {
            Section("Saved Recipes") {
                Text("Recipe list will go here")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    // placeholder: add recipe
                } label: {
                    Label("Add Recipe", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Recipe")
        .appToolbar()
    }
}

struct AddPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Add screen placeholder")
                .foregroundStyle(.secondary)
                .navigationTitle("Add")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}


#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}

