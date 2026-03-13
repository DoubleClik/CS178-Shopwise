import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var cartStore: CartStore
    
    @State private var query = ""
    @State private var selectedFilter: String = "All"
    @State private var results: [WalmartItem] = []
    @State private var isLoading = false
    @State private var errorText: String? = nil
    @State private var expandedItemId: Int? = nil

    @State private var pageSize = 50
    @State private var offset = 0

    @State private var isLoadingMore = false
    @State private var hasMore = true

    private let filters = ["All", "Ingredients", "Non-Ingredients"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // Title
                Text("ShopWise")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.top, 6)

                // Search bar (custom like your right screenshot)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search products...", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if !query.isEmpty {
                        Button {
                            query = ""
                            searchItems(reset: true)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                // Category chips row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filters, id: \.self) { f in
                            SearchCategoryChip(title: f, isSelected: selectedFilter == f) {
                                selectedFilter = f
                                searchItems(reset: true)   // ✅ ADD HERE
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                // Content
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading…")
                        Spacer()
                    }
                    .padding(.top, 24)
                } else if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .padding(.top, 10)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, item in
                            ProductCard(
                                imageURL: bestImageURL(for: item),
                                title: item.name,
                                unit: unitText(for: item),
                                priceText: formatPrice(item.retail_price),
                                descriptionText: nil, // link this to Supabase later
                                itemCountText: nil,   // link this to Supabase later
                                isExpanded: expandedItemId == item.id,
                                onToggle: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        if expandedItemId == item.id {
                                            expandedItemId = nil
                                        } else {
                                            expandedItemId = item.id
                                        }
                                    }
                                },
                                onAdd: {
                                    cartStore.add(id: String(item.id), name: item.name, unit: unitText(for: item) ?? "", price: item.retail_price ?? 0)
                                }
                            )
                            .onAppear {
                                // When the LAST item appears, load more
                                if index == filteredResults.count - 1 {
                                    searchItems(reset: false)
                                }
                            }
                        }                    }
                    .padding(.top, 4)
                }
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .appToolbar() // <-- uses your existing Settings/Profile toolbar
        .onChange(of: query) { _, _ in
            searchItems(reset: true)
        }
        .task {
            searchItems(reset: true)
        }
    }

    // MARK: - Filtering
    private var filteredResults: [WalmartItem] {
        switch selectedFilter {
        case "Ingredients":
            return results.filter { $0.ingredient == true }
        case "Non-Ingredients":
            return results.filter { $0.ingredient == false }
        default:
            return results
        }
    }

    // MARK: - Helpers (image/price/unit)
    private func bestImageURL(for item: WalmartItem) -> URL? {
        if let s = item.thumbnailImage, let url = URL(string: s), !s.isEmpty { return url }
        if let s = item.mediumImage, let url = URL(string: s), !s.isEmpty { return url }
        if let s = item.largeImage, let url = URL(string: s), !s.isEmpty { return url }
        return nil
    }

    private func formatPrice(_ p: Double?) -> String {
        guard let p else { return "Price unavailable" }
        return String(format: "$%.2f", p)
    }

    private func unitText(for item: WalmartItem) -> String? {
        // Your Supabase data doesn't include a unit column.
        // If classifiers contains something unit-like, show it; otherwise hide.
        let cls = (item.classifiers ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if cls.isEmpty { return nil }
        return cls
    }

    // MARK: - Supabase fetch
    private func searchItems(reset: Bool = true) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // If we're already loading more, don't double-fire
        if isLoadingMore { return }

        if reset {
            offset = 0
            results = []
            hasMore = true
        } else {
            // if we already know there are no more rows, stop
            if !hasMore { return }
        }

        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorText = nil

        Task {
            do {
                let ingredientOnly: Bool? = {
                    switch selectedFilter {
                    case "Ingredients": return true
                    case "Non-Ingredients": return false
                    default: return nil
                    }
                }()

                let newItems = try await auth.fetchWalmartItems(
                    search: trimmed.isEmpty ? nil : trimmed,
                    ingredientOnly: ingredientOnly,   // ✅ NEW
                    limit: pageSize,
                    offset: offset
                )

                await MainActor.run {
                    // Append results
                    results.append(contentsOf: newItems)

                    // Move offset forward
                    offset += newItems.count

                    // If we got fewer than pageSize, we reached the end
                    if newItems.count < pageSize { hasMore = false }

                    isLoading = false
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    errorText = "Search failed: \(error.localizedDescription)"
                    isLoading = false
                    isLoadingMore = false
                }
            }
        }
    }
}


struct SearchCategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.18) : Color(.systemGray6))
                .foregroundStyle(isSelected ? Color.blue : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ProductCard: View {
    let imageURL: URL?
    let title: String
    let unit: String?
    let priceText: String
    let descriptionText: String?
    let itemCountText: String?
    let isExpanded: Bool
    let onToggle: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 74, height: 74)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 74, height: 74)
                            .clipped()
                    case .failure:
                        Image(systemName: "photo")
                            .frame(width: 74, height: 74)
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                            .frame(width: 74, height: 74)
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture(perform: onToggle)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                        .onTapGesture(perform: onToggle)

                    if let unit, !unit.isEmpty {
                        Text(unit)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .onTapGesture(perform: onToggle)
                    }

                    Text(priceText)
                        .font(.headline)
                        .onTapGesture(perform: onToggle)
                }

                Spacer()

                Button(action: onAdd) {
                    HStack(spacing: 8) {
                        Image(systemName: "cart.badge.plus")
                        Text("Add")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.blue)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 160)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 200)
                                .clipped()
                        case .failure:
                            Image(systemName: "photo")
                                .frame(maxWidth: .infinity, minHeight: 160)
                                .foregroundStyle(.secondary)
                        @unknown default:
                            EmptyView()
                                .frame(maxWidth: .infinity, minHeight: 160)
                        }
                    }
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onTapGesture(perform: onToggle)

                    if let descriptionText, !descriptionText.isEmpty {
                        Text(descriptionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Description coming soon")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let itemCountText, !itemCountText.isEmpty {
                        Text("Item count: \(itemCountText)")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Item count: —")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemGray6).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
