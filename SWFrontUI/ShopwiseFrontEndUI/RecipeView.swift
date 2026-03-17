import SwiftUI

struct RecipeView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var cartStore: CartStore

    @State private var query = ""
    @State private var recipes: [RecipeRow] = []
    @State private var expandedID: Int? = nil
    @State private var isLoading = false
    @State private var errorText: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    @State private var pageSize = 20
    @State private var offset = 0
    @State private var hasMore = true
    @State private var isLoadingMore = false
    @State private var excludedIngredientsByRecipe: [Int: Set<String>] = [:]
    @State private var expandedInstructionIds: Set<Int> = []

    // Kroger matches keyed by recipe_id
    @State private var matchesByRecipe: [Int: [RecipeMatch]] = [:]
    @State private var loadingMatchesFor: Set<Int> = []

    private var filtered: [RecipeRow] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return recipes }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List { content }
            .listStyle(.plain)
            .navigationTitle("ShopWise")
            .searchable(text: $query, prompt: "Search recipes…")
            .appToolbar()
            .task { await loadRecipes(reset: true) }
            .onChange(of: query) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if Task.isCancelled { return }
                    await loadRecipes(reset: true)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack { Spacer(); ProgressView("Loading…"); Spacer() }
                .listRowSeparator(.hidden)
        } else if let errorText {
            Text(errorText).foregroundStyle(.red)
        } else {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, recipe in
                recipeSection(index: index, recipe: recipe)
            }
        }
    }

    private func recipeSection(index: Int, recipe: RecipeRow) -> some View {
        Section {
            Button {
                withAnimation(.snappy) {
                    if expandedID == recipe.id {
                        expandedID = nil
                    } else {
                        expandedID = recipe.id
                        loadMatchesIfNeeded(for: recipe.id)
                    }
                }
            } label: {
                recipeCard(recipe)
            }
            .buttonStyle(.plain)
            .onAppear {
                if index == filtered.count - 1 {
                    Task { await loadRecipes(reset: false) }
                }
            }

            if expandedID == recipe.id {
                recipeExpanded(recipe)
            }
        }
    }

    private func recipeCard(_ recipe: RecipeRow) -> some View {
        CardContainer {
            HStack(spacing: 14) {
                if let urlString = recipe.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure: Image(systemName: "fork.knife")
                        default: ProgressView()
                        }
                    }
                    .frame(width: 67, height: 67)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemGray5))
                        .frame(width: 67, height: 67)
                        .overlay(Image(systemName: "fork.knife").foregroundStyle(.secondary))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title).font(.headline).lineLimit(2)
                }

                Spacer()

                Image(systemName: expandedID == recipe.id ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recipeExpanded(_ recipe: RecipeRow) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {

                Text("Ingredients").font(.headline)

                let matches = matchesByRecipe[recipe.id] ?? []
                let isLoadingMatches = loadingMatchesFor.contains(recipe.id)

                if isLoadingMatches {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            ProgressView()
                            Text("Finding Kroger products…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)

                } else if matches.isEmpty {
                    ForEach(recipe.ingredientList, id: \.self) { item in
                        ingredientRow(recipeId: recipe.id, item: item)
                    }

                } else {
                    let grouped = groupedMatches(matches)
                    let ingredients = orderedIngredients(from: matches)

                    ForEach(ingredients, id: \.self) { item in
                        IngredientMatchRow(
                            ingredient: item,
                            matches: grouped[item] ?? [],
                            isExcluded: excludedIngredientsByRecipe[recipe.id]?.contains(item) == true,
                            onToggle: { toggleIngredient(recipeId: recipe.id, item: item) },
                            onAdd: { match in
                                cartStore.add(
                                    recipeId: String(recipe.id),
                                    recipeTitle: recipe.title,
                                    name: match.matched_name ?? item,
                                    unit: match.matched_size ?? "",
                                    price: match.min_price ?? 0
                                )
                            }
                        )
                    }
                }

                if let instructions = recipe.instructions,
                   !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider().padding(.vertical, 2)

                    Button {
                        withAnimation(.snappy) {
                            toggleInstructions(recipe.id)
                        }
                    } label: {
                        HStack {
                            Text("Instructions")
                                .font(.headline)
                            Spacer()
                            Image(systemName: expandedInstructionIds.contains(recipe.id) ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if expandedInstructionIds.contains(recipe.id) {
                        if !recipe.instructionSteps.isEmpty {
                            ForEach(Array(recipe.instructionSteps.enumerated()), id: \.offset) { index, step in
                                Text("Step \(index + 1): \(step)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(instructions).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    let excluded = excludedIngredientsByRecipe[recipe.id] ?? []
                    let matches = matchesByRecipe[recipe.id] ?? []
                    let grouped = groupedMatches(matches)
                    let ingredients = matches.isEmpty
                        ? recipe.ingredientList
                        : orderedIngredients(from: matches)

                    for item in ingredients where !excluded.contains(item) {
                        if let top = grouped[item]?.first {
                            cartStore.add(
                                recipeId: String(recipe.id),
                                recipeTitle: recipe.title,
                                name: top.matched_name ?? item,
                                unit: top.matched_size ?? "",
                                price: top.min_price ?? 0
                            )
                        } else {
                            cartStore.add(
                                recipeId: String(recipe.id),
                                recipeTitle: recipe.title,
                                name: item, unit: "", price: 0
                            )
                        }
                    }
                } label: {
                    let excluded = excludedIngredientsByRecipe[recipe.id] ?? []
                    let selectedCount = max(0, recipe.ingredientList.count - excluded.count)
                    VStack(spacing: 4) {
                        Text("\(selectedCount) selected")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Label("Add Selected Ingredients", systemImage: "cart.badge.plus")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

    private func groupedMatches(_ matches: [RecipeMatch]) -> [String: [RecipeMatch]] {
        var dict: [String: [RecipeMatch]] = [:]
        for match in matches {
            dict[match.raw_ingredient, default: []].append(match)
        }
        return dict
    }

    private func orderedIngredients(from matches: [RecipeMatch]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            if seen.insert(match.raw_ingredient).inserted {
                result.append(match.raw_ingredient)
            }
        }
        return result
    }

    private func loadMatchesIfNeeded(for recipeId: Int) {
        guard matchesByRecipe[recipeId] == nil,
              !loadingMatchesFor.contains(recipeId) else { return }
        loadingMatchesFor.insert(recipeId)
        Task {
            do {
                let fetched = try await auth.fetchRecipeMatches(recipeId: recipeId)
                await MainActor.run {
                    matchesByRecipe[recipeId] = fetched
                    loadingMatchesFor.remove(recipeId)
                }
            } catch {
                await MainActor.run {
                    matchesByRecipe[recipeId] = []
                    loadingMatchesFor.remove(recipeId)
                }
            }
        }
    }

    private func toggleIngredient(recipeId: Int, item: String) {
        var set = excludedIngredientsByRecipe[recipeId] ?? []
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
        excludedIngredientsByRecipe[recipeId] = set
    }

    private func toggleInstructions(_ recipeId: Int) {
        if expandedInstructionIds.contains(recipeId) {
            expandedInstructionIds.remove(recipeId)
        } else {
            expandedInstructionIds.insert(recipeId)
        }
    }

    private func ingredientRow(recipeId: Int, item: String) -> some View {
        let isExcluded = excludedIngredientsByRecipe[recipeId]?.contains(item) == true
        return Button { toggleIngredient(recipeId: recipeId, item: item) } label: {
            HStack(spacing: 10) {
                Image(systemName: isExcluded ? "minus.circle" : "checkmark.circle.fill")
                    .foregroundStyle(isExcluded ? Color.secondary : Color.green)
                Text(item)
                    .foregroundStyle(isExcluded ? Color.secondary : Color.primary)
                    .strikethrough(isExcluded, color: .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadRecipes(reset: Bool = true) async {
        if isLoadingMore { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if reset {
            offset = 0; recipes = []; hasMore = true; isLoading = true
        } else {
            if !hasMore { return }
            isLoadingMore = true
        }
        errorText = nil

        do {
            let fetched = try await auth.fetchRecipes(
                search: trimmed.isEmpty ? nil : trimmed,
                limit: pageSize, offset: offset
            )
            if reset { recipes = fetched } else { recipes.append(contentsOf: fetched) }
            offset += fetched.count
            if fetched.count < pageSize { hasMore = false }
        } catch {
            errorText = (error as NSError).localizedDescription
        }
        isLoading = false
        isLoadingMore = false
    }
}

// MARK: - Ingredient row with Kroger match

struct IngredientMatchRow: View {
    let ingredient: String
    let matches: [RecipeMatch]
    let isExcluded: Bool
    let onToggle: () -> Void
    let onAdd: (RecipeMatch) -> Void

    @State private var selectedRank = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: isExcluded ? "minus.circle" : "checkmark.circle.fill")
                        .foregroundStyle(isExcluded ? Color.secondary : Color.green)
                    Text(ingredient)
                        .font(.subheadline)
                        .foregroundStyle(isExcluded ? Color.secondary : Color.primary)
                        .strikethrough(isExcluded, color: .secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if !matches.isEmpty && !isExcluded {
                if matches.count > 1 {
                    Picker("", selection: $selectedRank) {
                        ForEach(matches.indices, id: \.self) { i in
                            Text(matches[i].displayPrice).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if selectedRank < matches.count {
                    let match = matches[selectedRank]
                    HStack(spacing: 10) {
                        AsyncImage(url: match.imageURL) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                                    .frame(width: 44, height: 44).clipped()
                            default:
                                Image(systemName: "photo")
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.matched_name ?? "")
                                .font(.caption.weight(.medium))
                                .lineLimit(2)
                            if let size = match.matched_size, !size.isEmpty {
                                Text(size).font(.caption2).foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(match.displayPrice)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)

                            Button { onAdd(match) } label: {
                                Image(systemName: "cart.badge.plus")
                                    .font(.system(size: 14))
                                    .padding(6)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray6).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
