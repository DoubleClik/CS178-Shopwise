import SwiftUI

struct CartView: View {
    @State private var showShoppingList = false
    @EnvironmentObject private var cartStore: CartStore
    @State private var expandedRecipeIds: Set<String> = []

    var body: some View {
        List {
            if cartStore.items.isEmpty {
                Section("Items") {
                    Text("Cart is empty")
                        .foregroundStyle(.secondary)
                }
            } else {
                if !recipeGroups.isEmpty {
                    Section("Recipes") {
                        ForEach(recipeGroups, id: \.id) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    toggle(group.id)
                                } label: {
                                    HStack {
                                        Text(group.title)
                                            .font(.headline)
                                        Spacer()
                                        Text("\(group.items.count) items")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: expandedRecipeIds.contains(group.id) ? "chevron.up" : "chevron.down")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                if expandedRecipeIds.contains(group.id) {
                                    ForEach(group.items) { item in
                                        itemRow(item)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Individual Items") {
                    if individualItems.isEmpty {
                        Text("No individual items")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(individualItems) { item in
                            itemRow(item)
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                cartStore.remove(individualItems[idx])
                            }
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

    private var recipeGroups: [RecipeGroup] {
        let items = cartStore.items
        var groups: [String: RecipeGroup] = [:]
        
        for item in items {
            guard let groupId = item.groupId, !groupId.isEmpty else { continue }
            let title = item.groupTitle ?? "Recipe"

            if let existing = groups[groupId] {
                var newItems = existing.items
                newItems.append(item)
                groups[groupId] = RecipeGroup(id: existing.id, title: existing.title, items: newItems)
            } else {
                groups[groupId] = RecipeGroup(id: groupId, title: title, items: [item])
            }
        }

        return groups.values
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var individualItems: [CartLineItem] {
        cartStore.items.filter { $0.groupId == nil }
    }

    private func toggle(_ id: String) {
        if expandedRecipeIds.contains(id) {
            expandedRecipeIds.remove(id)
        } else {
            expandedRecipeIds.insert(id)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: CartLineItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                if !item.unit.isEmpty {
                    Text(item.unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
}

private struct RecipeGroup: Identifiable {
    let id: String
    let title: String
    let items: [CartLineItem]
}
