import SwiftUI
import Combine

// Simple cart line item model (separate from your SwiftData Item model)
struct CartLineItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let unit: String
    let price: Double
    var quantity: Int

    init(id: UUID = UUID(), name: String, unit: String, price: Double, quantity: Int = 1) {
        self.id = id
        self.name = name
        self.unit = unit
        self.price = price
        self.quantity = quantity
    }

    var lineTotal: Double { price * Double(quantity) }
}

final class CartStore: ObservableObject {
    @Published private(set) var items: [CartLineItem] = []

    //amount of cart items
    var itemCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    var total: Double {
        items.reduce(0) { $0 + $1.lineTotal }
    }

    func add(name: String, unit: String, price: Double) {
        if let idx = items.firstIndex(where: { $0.name == name && $0.unit == unit && $0.price == price }) {
            items[idx].quantity += 1
        } else {
            items.append(CartLineItem(name: name, unit: unit, price: price))
        }
    }

    func increment(_ item: CartLineItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].quantity += 1
    }

    func decrement(_ item: CartLineItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].quantity -= 1
        if items[idx].quantity <= 0 {
            items.remove(at: idx)
        }
    }

    func remove(_ item: CartLineItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }
}
