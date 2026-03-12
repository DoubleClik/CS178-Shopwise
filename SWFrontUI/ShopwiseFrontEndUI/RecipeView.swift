import SwiftUI

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
