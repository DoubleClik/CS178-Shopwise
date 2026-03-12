import Foundation

struct Ingredient: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let unit: String
    let price: Double
    let imageURL: String?
    let imageName: String?

    init(
        id: String,
        name: String,
        unit: String,
        price: Double,
        imageURL: String? = nil,
        imageName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.price = price
        self.imageURL = imageURL
        self.imageName = imageName
    }
}
