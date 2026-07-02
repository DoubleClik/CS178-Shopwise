import Foundation

struct UserPreferences: Codable, Hashable {
    var dietPreferences: [String]
    var allergies: [String]

    static let empty = UserPreferences(
        dietPreferences: [],
        allergies: []
    )
}
