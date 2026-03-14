import SwiftUI
import Combine

// Simple cart line item model (separate from your SwiftData Item model)
struct CartLineItem: Identifiable, Hashable {
    let id: String
    let name: String
    let unit: String
    let price: Double
    var quantity: Int
    let groupId: String?
    let groupTitle: String?

    init(id: String = String(),name: String,unit: String,price: Double, quantity: Int = 1,groupId: String? = nil,groupTitle: String? = nil){
            self.id = id
            self.name = name
            self.unit = unit
            self.price = price
            self.quantity = quantity
            self.groupId = groupId
            self.groupTitle = groupTitle
    }

    var lineTotal: Double{
        price * Double(quantity)
    }
}

final class CartStore: ObservableObject {
    @Published private(set) var items: [CartLineItem] = []

    var itemCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    var total: Double {
        items.reduce(0) { $0 + $1.lineTotal }
    }

    func add(product: Product) {
        add(id: product.id, name: product.name, unit: product.unit, price: product.price)
    }

    func add(ingredient: Ingredient) {
        add(id: ingredient.id, name: ingredient.name, unit: ingredient.unit, price: ingredient.price)
    }

    func add(name: String, unit: String, price: Double) {
        add(id: name, name: name, unit: unit, price: price)
    }

    func add(id: String, name: String, unit: String, price: Double) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].quantity += 1
        } else {
            items.append(
                CartLineItem(
                    id: id,
                    name: name,
                    unit: unit,
                    price: price,
                    quantity: 1
                )
            )
        }
    }

    func add(recipeId: String, recipeTitle: String, name: String, unit: String, price: Double) {
        let id = "\(recipeId)::\(name)"
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].quantity += 1
        } else {
            items.append(
                CartLineItem(
                    id: id,
                    name: name,
                    unit: unit,
                    price: price,
                    quantity: 1,
                    groupId: recipeId,
                    groupTitle: recipeTitle
                )
            )
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
