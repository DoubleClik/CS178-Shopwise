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
    
    private var filtered: [RecipeRow] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recipes
        }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
        
    var body: some View {
        List {
            content
        }
        .listStyle(.plain)
        .navigationTitle("ShopWise")
        .searchable(text: $query, prompt: "Search recipes…")
        .appToolbar()
        .task {
            await loadRecipes(reset: true)
        }
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
            HStack {
                Spacer()
                ProgressView("Loading…")
                Spacer()
            }
            .listRowSeparator(.hidden)

        } else if let errorText {
            Text(errorText)
                .foregroundStyle(.red)

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
                    expandedID = (expandedID == recipe.id) ? nil : recipe.id
                }
            } label: {
                recipeCard(recipe)
            }
            .buttonStyle(.plain)
            .onAppear {
                if index == filtered.count - 1 {
                    Task {
                        await loadRecipes(reset: false)
                    }
                }
            }

            if expandedID == recipe.id {
                recipeExpanded(recipe)
            }
        }
    }
    
    private func recipeCard(_ recipe: RecipeRow) -> some View {
        CardContainer {
            HStack(spacing: 12) {

                if let urlString = recipe.imageURL,
                   let url = URL(string: urlString) {

                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure(_):
                            Image(systemName: "fork.knife")
                        default:
                            ProgressView()
                        }
                    }
                    .frame(width: 54, height: 54)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 54, height: 54)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text("\(recipe.difficultyText) • \(recipe.estimatedMinutes) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: expandedID == recipe.id ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recipeExpanded(_ recipe: RecipeRow) -> some View {
        CardContainer {

            Text("Ingredients")
                .font(.headline)

            ForEach(recipe.ingredientList, id: \.self) { item in
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text(item)
                }
            }

            Button {
                for item in recipe.ingredientList {
                    cartStore.add(id: "\(recipe.id)::\(item)", name: item, unit: "", price: 0)
                }
            } label: {
                Label("Add Ingredients to Cart", systemImage: "cart.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    @MainActor
    private func loadRecipes(reset: Bool = true) async {
        if isLoadingMore { return }
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if reset {
            offset = 0
            recipes = []
            hasMore = true
            isLoading = true
        } else {
            if !hasMore { return }
            isLoadingMore = true
        }
        
        errorText = nil
        
        do {
            let fetched = try await auth.fetchRecipes(
                search: trimmed.isEmpty ? nil : trimmed,
                limit: pageSize,
                offset: offset
            )
            
            if reset {
                recipes = fetched
            } else {
                recipes.append(contentsOf: fetched)
            }
            
            offset += fetched.count
            if fetched.count < pageSize {
                hasMore = false
            }
        } catch {
            errorText = (error as NSError).localizedDescription
        }
        
        isLoading = false
        isLoadingMore = false
    }
}
