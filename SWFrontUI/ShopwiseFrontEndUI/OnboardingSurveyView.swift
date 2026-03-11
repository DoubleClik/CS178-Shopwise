import SwiftUI

struct OnboardingSurveyView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDiets: Set<String> = []
    @State private var selectedAllergies: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    let dietOptions = [
        "Vegetarian", "Vegan", "Pescatarian",
        "Keto", "Gluten-Free", "Dairy-Free",
        "Halal", "Kosher"
    ]

    let allergyOptions = [
        "Peanuts", "Tree Nuts", "Dairy", "Eggs",
        "Soy", "Wheat", "Shellfish", "Fish", "Sesame"
    ]

    var onComplete: (() -> Void)? = nil

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

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task {
                        await savePreferences()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Preferences")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .navigationTitle("Your Preferences")
        .task {
            await loadPreferences()
        }
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func loadPreferences() async {
        do {
            if let prefs = try await auth.fetchUserPreferences() {
                selectedDiets = Set(prefs.dietPreferences)
                selectedAllergies = Set(prefs.allergies)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func savePreferences() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let prefs = UserPreferences(
                dietPreferences: Array(selectedDiets).sorted(),
                allergies: Array(selectedAllergies).sorted()
            )

            try await auth.saveUserPreferences(prefs)

            if let onComplete {
                onComplete()
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
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
