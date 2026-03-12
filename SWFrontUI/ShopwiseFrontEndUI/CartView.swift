import SwiftUI

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
