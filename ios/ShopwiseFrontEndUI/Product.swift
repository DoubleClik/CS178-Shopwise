import Foundation

struct Product: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: String
    let unit: String
    let price: Double
    let imageURL: String?
    let imageName: String?

    init(
        id: String,
        name: String,
        category: String,
        unit: String,
        price: Double,
        imageURL: String? = nil,
        imageName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.unit = unit
        self.price = price
        self.imageURL = imageURL
        self.imageName = imageName
    }
}
