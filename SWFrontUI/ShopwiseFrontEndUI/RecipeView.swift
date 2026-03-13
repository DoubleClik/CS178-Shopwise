//
//  RecipeModels.swift
//  ShopwiseFrontEndUI
//
//  Created by Nicholas Castellanos on 3/11/26.
//

import Foundation

struct RecipeRow: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let ingredients: String?
    let instructions: String?
    let imageName: String?
    let cleanedIngredients: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title = "Title"
        case ingredients = "Ingredients"
        case instructions = "Instructions"
        case imageName = "Image_Name"
        case cleanedIngredients = "Cleaned_Ingredients"
        case imageURL = "image_url"
    }

    var ingredientList: [String] {
        guard let ingredients, !ingredients.isEmpty else { return [] }

        let trimmed = ingredients
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        return trimmed
            .components(separatedBy: "',")
            .map {
                $0.replacingOccurrences(of: "'", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    var difficultyText: String {
        let count = ingredientList.count
        if count <= 5 { return "Easy" }
        if count <= 10 { return "Medium" }
        return "Hard"
    }

    var estimatedMinutes: Int {
        let text = instructions ?? ""
        let sentences = text.components(separatedBy: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return max(10, min(60, sentences * 5))
    }
}
