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
        "Soy", "Wheat", "Shellfish", "Fish"
    ]

    var onComplete: (() -> Void)? = nil

    var body: some View {
        List {
            Section {
                PreferenceChipGrid(
                    options: dietOptions,
                    selected: selectedDiets,
                    onToggle: { toggle($0, in: &selectedDiets) }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if !selectedDiets.isEmpty {
                    Button("Clear Diet Preferences") {
                        selectedDiets.removeAll()
                    }
                }
            } header: {
                Text("Diet Preferences")
            } footer: {
                Text("Pick any that apply. You can update these anytime.")
            }

            Section {
                PreferenceChipGrid(
                    options: allergyOptions,
                    selected: selectedAllergies,
                    onToggle: { toggle($0, in: &selectedAllergies) }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if !selectedAllergies.isEmpty {
                    Button("Clear Allergies") {
                        selectedAllergies.removeAll()
                    }
                }
            } header: {
                Text("Allergies")
            } footer: {
                Text("We’ll filter recipes and suggestions based on these.")
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

private struct PreferenceChipGrid: View {
    let options: [String]
    let selected: Set<String>
    let onToggle: (String) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { option in
                let isSelected = selected.contains(option)
                Button {
                    onToggle(option)
                } label: {
                    Text(option)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Theme.primary.opacity(0.18) : Color(.systemGray6))
                        .foregroundStyle(isSelected ? Theme.primary : Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}
