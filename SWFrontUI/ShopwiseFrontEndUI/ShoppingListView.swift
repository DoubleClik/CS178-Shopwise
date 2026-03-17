import SwiftUI

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
            if cartStore.items.isEmpty {
                Section("Shopping List") {
                    Text("No items to shop for.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if !recipeGroups.isEmpty {
                    ForEach(recipeGroups) { group in
                        Section(group.title) {
                            ForEach(group.items) { item in
                                itemRow(item)
                            }
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

    @ViewBuilder
    private func itemRow(_ item: CartLineItem) -> some View {
        Button {
            toggle(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: checkedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .strikethrough(checkedIDs.contains(item.id))
                    if !item.unit.isEmpty {
                        Text("\(item.quantity) × \(item.unit)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(item.quantity)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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

private struct RecipeGroup: Identifiable {
    let id: String
    let title: String
    let items: [CartLineItem]
}
