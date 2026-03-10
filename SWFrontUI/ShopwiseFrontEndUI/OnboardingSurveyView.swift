import SwiftUI

struct OnboardingSurveyView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("savedDietPreferences") private var savedDietPreferencesData = Data()
    @AppStorage("savedAllergies") private var savedAllergiesData = Data()

    @State private var selectedDiets: Set<String> = []
    @State private var selectedAllergies: Set<String> = []

    let dietOptions = [
        "Vegetarian", "Vegan", "Pescatarian",
        "Keto", "Gluten-Free", "Dairy-Free",
        "Halal", "Kosher"
    ]

    let allergyOptions = [
        "Peanuts", "Tree Nuts", "Dairy", "Eggs",
        "Soy", "Wheat", "Shellfish", "Fish", "Sesame"
    ]

    var body: some View {
        List {
            Section("Diet Preferences") {
                ForEach(dietOptions, id: \.self) { option in
                    PreferenceRow(
                        title: option,
                        isSelected: selectedDiets.contains(option)
                    ) {
                        toggle(option, in: &selectedDiets)
                    }
                }
            }

            Section("Allergies") {
                ForEach(allergyOptions, id: \.self) { option in
                    PreferenceRow(
                        title: option,
                        isSelected: selectedAllergies.contains(option)
                    ) {
                        toggle(option, in: &selectedAllergies)
                    }
                }
            }

            Section {
                Button {
                    savePreferences()
                } label: {
                    Text("Save Preferences")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Your Preferences")
        .onAppear {
            loadSavedPreferences()
        }
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func savePreferences() {
        if let dietData = try? JSONEncoder().encode(Array(selectedDiets).sorted()) {
            savedDietPreferencesData = dietData
        }

        if let allergyData = try? JSONEncoder().encode(Array(selectedAllergies).sorted()) {
            savedAllergiesData = allergyData
        }

        hasCompletedOnboarding = true
        dismiss()
    }

    private func loadSavedPreferences() {
        if let savedDiets = try? JSONDecoder().decode([String].self, from: savedDietPreferencesData) {
            selectedDiets = Set(savedDiets)
        }

        if let savedAllergies = try? JSONDecoder().decode([String].self, from: savedAllergiesData) {
            selectedAllergies = Set(savedAllergies)
        }
    }
}

struct PreferenceRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
