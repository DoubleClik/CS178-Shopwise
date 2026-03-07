import Foundation

struct Recipe: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let difficulty: String
    let minutes: Int
    let imageURL: String?
    let imageName: String?
    let ingredients: [Ingredient]

    init(
        id: String,
        name: String,
        difficulty: String,
        minutes: Int,
        imageURL: String? = nil,
        imageName: String? = nil,
        ingredients: [Ingredient]
    ) {
        self.id = id
        self.name = name
        self.difficulty = difficulty
        self.minutes = minutes
        self.imageURL = imageURL
        self.imageName = imageName
        self.ingredients = ingredients
    }
}
