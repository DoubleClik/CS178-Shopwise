import Foundation
import NaturalLanguage

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

        let trimmed = ingredients.trimmingCharacters(in: .whitespacesAndNewlines)

        if let singleQuoted = extractQuotedItems(from: trimmed, quote: "'"), !singleQuoted.isEmpty {
            return singleQuoted
        }
        if let doubleQuoted = extractQuotedItems(from: trimmed, quote: "\""), !doubleQuoted.isEmpty {
            return doubleQuoted
        }

        let fallback = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return fallback
    }

    private func extractQuotedItems(from text: String, quote: String) -> [String]? {
        let pattern = "\(quote)([^\\\(quote)]*)\(quote)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)

        let items = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: text) else { return nil }
            let value = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        return items.isEmpty ? nil : items
    }

    var instructionSteps: [String] {
        guard let instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let normalized = instructions
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let paragraphs = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.count >= 2 {
            return paragraphs
        }

        if #available(iOS 12.0, *) {
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = normalized
            var steps: [String] = []
            tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
                let sentence = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    steps.append(sentence)
                }
                return true
            }
            if !steps.isEmpty {
                return steps
            }
        }

        return normalized
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /*var difficultyText: String {
        let count = ingredientList.count
        if count <= 5 { return "Easy" }
        if count <= 10 { return "Medium" }
        return "Hard"
    }

    var estimatedMinutes: Int {
        let text = instructions ?? ""
        let sentences = text.components(separatedBy: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return max(10, min(60, sentences * 5))
    }*/
}
