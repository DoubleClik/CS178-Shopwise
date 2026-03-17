import SwiftUI

struct CartView: View {
    @State private var showShoppingList = false
    @EnvironmentObject private var cartStore: CartStore
    @State private var expandedRecipeIds: Set<String> = []

    var body: some View {
        List {
            if !cartStore.items.isEmpty {
                Section("Summary") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Items")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(cartStore.itemCount)")
                                .font(.title3.weight(.semibold))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Total")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(String(format: "$%.2f", cartStore.total))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }

            if cartStore.items.isEmpty {
                Section("Items") {
                    Text("Cart is empty")
                        .foregroundStyle(.secondary)
                }
            } else {
                if !recipeGroups.isEmpty {
                    Section("Recipes") {
                        ForEach(recipeGroups, id: \.id) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    toggle(group.id)
                                } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.title)
                                                .font(.headline)
                                            Text("\(group.items.count) items • \(formatCurrency(groupSubtotal(for: group)))")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: expandedRecipeIds.contains(group.id) ? "chevron.up" : "chevron.down")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                if expandedRecipeIds.contains(group.id) {
                                    Divider()
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                        itemRow(item)
                                        if index != group.items.count - 1 {
                                            Divider()
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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

            Section {
                Button {
                    showShoppingList = true
                } label: {
                    Text("Checkout")
                        .frame(maxWidth: .infinity)
                }
                .disabled(cartStore.items.isEmpty)
            }

            if !cartStore.items.isEmpty {
                Section {
                    Button(role: .destructive) {
                        cartStore.clear()
                    } label: {
                        Text("Clear Cart")
                    }
                }
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

    private func groupSubtotal(for group: RecipeGroup) -> Double {
        group.items.reduce(0) { $0 + ($1.price * Double($1.quantity)) }
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

private struct RecipeGroup: Identifiable {
    let id: String
    let title: String
    let items: [CartLineItem]
}
