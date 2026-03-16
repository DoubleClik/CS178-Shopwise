//import SwiftUI
//
//struct SearchView: View {
//    @EnvironmentObject private var auth: AuthManager
//    @EnvironmentObject private var cartStore: CartStore
//
//    @State private var query = ""
//    @State private var selectedFilter: String = "All"
//    @State private var results: [WalmartItem] = []
//    @State private var isLoading = false
//    @State private var errorText: String? = nil
//
//    @State private var pageSize = 50
//    @State private var offset = 0
//
//    @State private var isLoadingMore = false
//    @State private var hasMore = true
//
//    private let filters = ["All", "Ingredients", "Non-Ingredients"]
//
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 14) {
//
//                // Title
//                Text("ShopWise")
//                    .font(.system(size: 34, weight: .bold))
//                    .padding(.top, 6)
//
//                // Search bar (custom like your right screenshot)
//                HStack(spacing: 10) {
//                    Image(systemName: "magnifyingglass")
//                        .foregroundStyle(.secondary)
//
//                    TextField("Search products...", text: $query)
//                        .textInputAutocapitalization(.never)
//                        .autocorrectionDisabled(true)
//
//                    if !query.isEmpty {
//                        Button {
//                            query = ""
//                            searchItems(reset: true)
//                        } label: {
//                            Image(systemName: "xmark")
//                                .font(.system(size: 12, weight: .bold))
//                                .foregroundStyle(.secondary)
//                                .padding(10)
//                                .background(.ultraThinMaterial)
//                                .clipShape(Circle())
//                        }
//                    }
//                }
//                .padding(.horizontal, 14)
//                .padding(.vertical, 12)
//                .background(Color(.systemGray6))
//                .clipShape(RoundedRectangle(cornerRadius: 18))
//
//                // Category chips row
//                ScrollView(.horizontal, showsIndicators: false) {
//                    HStack(spacing: 10) {
//                        ForEach(filters, id: \.self) { f in
//                            SearchCategoryChip(title: f, isSelected: selectedFilter == f) {
//                                selectedFilter = f
//                                searchItems(reset: true)   // ✅ ADD HERE
//                            }
//                        }
//                    }
//                    .padding(.vertical, 2)
//                }
//
//                // Content
//                if isLoading {
//                    HStack {
//                        Spacer()
//                        ProgressView("Loading…")
//                        Spacer()
//                    }
//                    .padding(.top, 24)
//                } else if let errorText {
//                    Text(errorText)
//                        .foregroundStyle(.red)
//                        .padding(.top, 10)
//                } else {
//                    LazyVStack(spacing: 14) {
//                        ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, item in
//                            ProductCard(
//                                imageURL: bestImageURL(for: item),
//                                title: item.name,
//                                unit: unitText(for: item),
//                                priceText: formatPrice(item.retail_price),
//                                onAdd: {
//                                    cartStore.add(id: String(item.id), name: item.name, unit: unitText(for: item) ?? "", price: item.retail_price ?? 0)
//                                }
//                            )
//                            .onAppear {
//                                // When the LAST item appears, load more
//                                if index == filteredResults.count - 1 {
//                                    searchItems(reset: false)
//                                }
//                            }
//                        }                    }
//                    .padding(.top, 4)
//                }
//
//                Spacer(minLength: 20)
//            }
//            .padding(.horizontal, 16)
//            .padding(.bottom, 20)
//        }
//        .background(Color(.systemBackground))
//        .navigationBarTitleDisplayMode(.inline)
//        .appToolbar() // <-- uses your existing Settings/Profile toolbar
//        .onChange(of: query) { _, _ in
//            searchItems(reset: true)
//        }
//        .task {
//            searchItems(reset: true)
//        }
//    }
//
//    // MARK: - Filtering
//    private var filteredResults: [WalmartItem] {
//        switch selectedFilter {
//        case "Ingredients":
//            return results.filter { $0.ingredient == true }
//        case "Non-Ingredients":
//            return results.filter { $0.ingredient == false }
//        default:
//            return results
//        }
//    }
//
//    // MARK: - Helpers (image/price/unit)
//    private func bestImageURL(for item: WalmartItem) -> URL? {
//        if let s = item.thumbnailImage, let url = URL(string: s), !s.isEmpty { return url }
//        if let s = item.mediumImage, let url = URL(string: s), !s.isEmpty { return url }
//        if let s = item.largeImage, let url = URL(string: s), !s.isEmpty { return url }
//        return nil
//    }
//
//    private func formatPrice(_ p: Double?) -> String {
//        guard let p else { return "Price unavailable" }
//        return String(format: "$%.2f", p)
//    }
//
//    private func unitText(for item: WalmartItem) -> String? {
//        // Your Supabase data doesn't include a unit column.
//        // If classifiers contains something unit-like, show it; otherwise hide.
//        let cls = (item.classifiers ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
//        if cls.isEmpty { return nil }
//        return cls
//    }
//
//    // MARK: - Supabase fetch
//    private func searchItems(reset: Bool = true) {
//        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
//
//        // If we're already loading more, don't double-fire
//        if isLoadingMore { return }
//
//        if reset {
//            offset = 0
//            results = []
//            hasMore = true
//        } else {
//            // if we already know there are no more rows, stop
//            if !hasMore { return }
//        }
//
//        if reset {
//            isLoading = true
//        } else {
//            isLoadingMore = true
//        }
//        errorText = nil
//
//        Task {
//            do {
//                let ingredientOnly: Bool? = {
//                    switch selectedFilter {
//                    case "Ingredients": return true
//                    case "Non-Ingredients": return false
//                    default: return nil
//                    }
//                }()
//
//                let newItems = try await auth.fetchWalmartItems(
//                    search: trimmed.isEmpty ? nil : trimmed,
//                    ingredientOnly: ingredientOnly,   // ✅ NEW
//                    limit: pageSize,
//                    offset: offset
//                )
//
//                await MainActor.run {
//                    // Append results
//                    results.append(contentsOf: newItems)
//
//                    // Move offset forward
//                    offset += newItems.count
//
//                    // If we got fewer than pageSize, we reached the end
//                    if newItems.count < pageSize { hasMore = false }
//
//                    isLoading = false
//                    isLoadingMore = false
//                }
//            } catch {
//                await MainActor.run {
//                    errorText = "Search failed: \(error.localizedDescription)"
//                    isLoading = false
//                    isLoadingMore = false
//                }
//            }
//        }
//    }
//}
//
//
//struct SearchCategoryChip: View {
//    let title: String
//    let isSelected: Bool
//    let action: () -> Void
//
//    var body: some View {
//        Button(action: action) {
//            Text(title)
//                .font(.subheadline.weight(.semibold))
//                .padding(.horizontal, 14)
//                .padding(.vertical, 8)
//                .background(isSelected ? Color.blue.opacity(0.18) : Color(.systemGray6))
//                .foregroundStyle(isSelected ? Color.blue : Color.primary)
//                .clipShape(Capsule())
//        }
//        .buttonStyle(.plain)
//    }
//}
//
//struct ProductCard: View {
//    let imageURL: URL?
//    let title: String
//    let unit: String?
//    let priceText: String
//    let onAdd: () -> Void
//
//    var body: some View {
//        HStack(spacing: 14) {
//            AsyncImage(url: imageURL) { phase in
//                switch phase {
//                case .empty:
//                    ProgressView()
//                        .frame(width: 74, height: 74)
//                case .success(let image):
//                    image
//                        .resizable()
//                        .scaledToFill()
//                        .frame(width: 74, height: 74)
//                        .clipped()
//                case .failure:
//                    Image(systemName: "photo")
//                        .frame(width: 74, height: 74)
//                        .foregroundStyle(.secondary)
//                @unknown default:
//                    EmptyView()
//                        .frame(width: 74, height: 74)
//                }
//            }
//            .background(Color(.systemGray6))
//            .clipShape(RoundedRectangle(cornerRadius: 16))
//
//            VStack(alignment: .leading, spacing: 6) {
//                Text(title)
//                    .font(.headline)
//                    .lineLimit(2)
//
//                if let unit, !unit.isEmpty {
//                    Text(unit)
//                        .font(.subheadline)
//                        .foregroundStyle(.secondary)
//                        .lineLimit(1)
//                }
//
//                Text(priceText)
//                    .font(.headline)
//            }
//
//            Spacer()
//
//            Button(action: onAdd) {
//                HStack(spacing: 8) {
//                    Image(systemName: "cart.badge.plus")
//                    Text("Add")
//                }
//                .font(.subheadline.weight(.semibold))
//                .padding(.horizontal, 14)
//                .padding(.vertical, 10)
//                .foregroundStyle(.white)
//                .background(Color.blue)
//                .clipShape(Capsule())
//            }
//            .buttonStyle(.plain)
//        }
//        .padding(14)
//        .background(Color(.systemGray6).opacity(0.65))
//        .clipShape(RoundedRectangle(cornerRadius: 18))
//    }
//}

//import SwiftUI
//
//struct SearchView: View {
//    @EnvironmentObject private var auth: AuthManager
//    @EnvironmentObject private var cartStore: CartStore
//
//    @State private var query = ""
//    @State private var selectedFilter: String = "All"
//    @State private var results: [KrogerItem] = []
//    @State private var isLoading = false
//    @State private var errorText: String? = nil
//
//    @State private var pageSize = 50
//    @State private var offset = 0
//    @State private var isLoadingMore = false
//    @State private var hasMore = true
//
//    private let filters = ["All", "Ingredients", "Non-Ingredients"]
//
//    // All classifiers that represent cooking/food ingredients
//    // Maps exactly to the classifier values in kroger_ingredients2
//    private let ingredientClassifiers: Set<String> = [
//        "PRODUCE",      // fresh fruit, vegetables, herbs
//        "PROTEIN",      // meat, poultry, seafood, eggs
//        "DAIRY",        // milk, cheese, butter, cream
//        "GRAIN",        // rice, pasta, bread, flour
//        "SPICE",        // herbs, spices, seasonings
//        "CONDIMENT",    // sauces, dressings, vinegars
//        "OIL_FAT",      // oils, butter, shortening
//        "BAKING",       // flour, sugar, baking powder
//        "CANNED_GOOD",  // canned tomatoes, beans, broth
//        "NUT_SEED",     // nuts, seeds, nut butters
//        "FRESH_HERB",   // fresh herbs (subset of PRODUCE)
//        "SWEETENER",    // sugar, honey, syrup
//        "THICKENER",    // cornstarch, gelatin, arrowroot
//        "ALCOHOL",      // wine, beer, spirits for cooking
//    ]
//
//    // Human-readable label → classifier value for filter chips
//    // Extend this if you want more granular category tabs
//    private let classifierLabels: [(label: String, classifier: String?)] = [
//        ("All",              nil),
//        ("Produce",          "PRODUCE"),
//        ("Protein",          "PROTEIN"),
//        ("Dairy",            "DAIRY"),
//        ("Pantry",           nil),      // covers GRAIN + BAKING + CANNED_GOOD
//        ("Spices",           "SPICE"),
//    ]
//
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 14) {
//
//                Text("ShopWise")
//                    .font(.system(size: 34, weight: .bold))
//                    .padding(.top, 6)
//
//                // Search bar
//                HStack(spacing: 10) {
//                    Image(systemName: "magnifyingglass")
//                        .foregroundStyle(.secondary)
//
//                    TextField("Search products...", text: $query)
//                        .textInputAutocapitalization(.never)
//                        .autocorrectionDisabled(true)
//
//                    if !query.isEmpty {
//                        Button {
//                            query = ""
//                            searchItems(reset: true)
//                        } label: {
//                            Image(systemName: "xmark")
//                                .font(.system(size: 12, weight: .bold))
//                                .foregroundStyle(.secondary)
//                                .padding(10)
//                                .background(.ultraThinMaterial)
//                                .clipShape(Circle())
//                        }
//                    }
//                }
//                .padding(.horizontal, 14)
//                .padding(.vertical, 12)
//                .background(Color(.systemGray6))
//                .clipShape(RoundedRectangle(cornerRadius: 18))
//
//                // Filter chips
//                ScrollView(.horizontal, showsIndicators: false) {
//                    HStack(spacing: 10) {
//                        ForEach(filters, id: \.self) { f in
//                            SearchCategoryChip(title: f, isSelected: selectedFilter == f) {
//                                selectedFilter = f
//                                searchItems(reset: true)
//                            }
//                        }
//                    }
//                    .padding(.vertical, 2)
//                }
//
//                // Content
//                if isLoading {
//                    HStack {
//                        Spacer()
//                        ProgressView("Loading…")
//                        Spacer()
//                    }
//                    .padding(.top, 24)
//                } else if let errorText {
//                    Text(errorText)
//                        .foregroundStyle(.red)
//                        .padding(.top, 10)
//                } else {
//                    LazyVStack(spacing: 14) {
//                        ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, item in
//                            ProductCard(
//                                imageURL: item.imageURL,
//                                title: item.name,
//                                unit: item.size,
//                                priceText: item.displayPrice(),  // pass selectedStoreId here when available
//                                onAdd: {
//                                    cartStore.add(
//                                        id: String(item.productId),
//                                        name: item.name,
//                                        unit: item.size ?? "",
//                                        price: item.minPrice ?? 0
//                                    )
//                                }
//                            )
//                            .onAppear {
//                                if index == filteredResults.count - 1 {
//                                    searchItems(reset: false)
//                                }
//                            }
//                        }
//                    }
//                    .padding(.top, 4)
//                }
//
//                Spacer(minLength: 20)
//            }
//            .padding(.horizontal, 16)
//            .padding(.bottom, 20)
//        }
//        .background(Color(.systemBackground))
//        .navigationBarTitleDisplayMode(.inline)
//        .appToolbar()
//        .onChange(of: query) { _, _ in
//            searchItems(reset: true)
//        }
//        .task {
//            searchItems(reset: true)
//        }
//    }
//
//    // MARK: - Filter by classifier
//    private var filteredResults: [KrogerItem] {
//        switch selectedFilter {
//        case "Ingredients":
//            // Show only items whose classifier is in the food ingredient set
//            return results.filter { item in
//                guard let cls = item.classifier else { return false }
//                return ingredientClassifiers.contains(cls)
//            }
//        case "Non-Ingredients":
//            // Show items whose classifier is NOT a cooking ingredient
//            // (household, personal care, pet food, etc.)
//            return results.filter { item in
//                guard let cls = item.classifier else { return true }
//                return !ingredientClassifiers.contains(cls)
//            }
//        default:
//            return results
//        }
//    }
//
//    // MARK: - Fetch
//    private func searchItems(reset: Bool = true) {
//        if isLoadingMore { return }
//
//        if reset {
//            offset = 0
//            results = []
//            hasMore = true
//        } else {
//            if !hasMore { return }
//        }
//
//        if reset { isLoading = true } else { isLoadingMore = true }
//        errorText = nil
//
//        Task {
//            do {
//                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
//                let newItems = try await auth.fetchKrogerItems(
//                    search: trimmed.isEmpty ? nil : trimmed,
//                    limit: pageSize,
//                    offset: offset
//                )
//
//                await MainActor.run {
//                    results.append(contentsOf: newItems)
//                    offset += newItems.count
//                    if newItems.count < pageSize { hasMore = false }
//                    isLoading = false
//                    isLoadingMore = false
//                }
//            } catch {
//                await MainActor.run {
//                    errorText = "Search failed: \(error.localizedDescription)"
//                    isLoading = false
//                    isLoadingMore = false
//                }
//            }
//        }
//    }
//}
//
//// MARK: - Subviews
//
//struct SearchCategoryChip: View {
//    let title: String
//    let isSelected: Bool
//    let action: () -> Void
//
//    var body: some View {
//        Button(action: action) {
//            Text(title)
//                .font(.subheadline.weight(.semibold))
//                .padding(.horizontal, 14)
//                .padding(.vertical, 8)
//                .background(isSelected ? Color.blue.opacity(0.18) : Color(.systemGray6))
//                .foregroundStyle(isSelected ? Color.blue : Color.primary)
//                .clipShape(Capsule())
//        }
//        .buttonStyle(.plain)
//    }
//}
//
//struct ProductCard: View {
//    let imageURL: URL?
//    let title: String
//    let unit: String?
//    let priceText: String
//    let onAdd: () -> Void
//
//    var body: some View {
//        HStack(spacing: 14) {
//            AsyncImage(url: imageURL) { phase in
//                switch phase {
//                case .empty:
//                    ProgressView().frame(width: 74, height: 74)
//                case .success(let image):
//                    image.resizable().scaledToFill()
//                        .frame(width: 74, height: 74).clipped()
//                case .failure:
//                    Image(systemName: "photo")
//                        .frame(width: 74, height: 74).foregroundStyle(.secondary)
//                @unknown default:
//                    EmptyView().frame(width: 74, height: 74)
//                }
//            }
//            .background(Color(.systemGray6))
//            .clipShape(RoundedRectangle(cornerRadius: 16))
//
//            VStack(alignment: .leading, spacing: 6) {
//                Text(title)
//                    .font(.headline)
//                    .lineLimit(2)
//
//                if let unit, !unit.isEmpty {
//                    Text(unit)
//                        .font(.subheadline)
//                        .foregroundStyle(.secondary)
//                        .lineLimit(1)
//                }
//
//                Text(priceText)
//                    .font(.headline)
//            }
//
//            Spacer()
//
//            Button(action: onAdd) {
//                HStack(spacing: 8) {
//                    Image(systemName: "cart.badge.plus")
//                    Text("Add")
//                }
//                .font(.subheadline.weight(.semibold))
//                .padding(.horizontal, 14)
//                .padding(.vertical, 10)
//                .foregroundStyle(.white)
//                .background(Color.blue)
//                .clipShape(Capsule())
//            }
//            .buttonStyle(.plain)
//        }
//        .padding(14)
//        .background(Color(.systemGray6).opacity(0.65))
//        .clipShape(RoundedRectangle(cornerRadius: 18))
//    }
//}

import SwiftUI

// MARK: - Classifier tab definition
struct ClassifierTab: Identifiable, Equatable {
    let id: String       // actual DB value or "All"
    let label: String    // display name
    let icon: String     // SF Symbol

    static let all: [ClassifierTab] = [
        ClassifierTab(id: "All",         label: "All",        icon: "square.grid.2x2"),
        ClassifierTab(id: "PRODUCE",     label: "Produce",    icon: "leaf"),
        ClassifierTab(id: "PROTEIN",     label: "Protein",    icon: "fork.knife"),
        ClassifierTab(id: "DAIRY",       label: "Dairy",      icon: "drop"),
        ClassifierTab(id: "GRAIN",       label: "Grain",      icon: "bag"),
        ClassifierTab(id: "SPICE",       label: "Spices",     icon: "sparkles"),
        ClassifierTab(id: "CONDIMENT",   label: "Condiments", icon: "mug"),
        ClassifierTab(id: "OIL_FAT",     label: "Oils",       icon: "flame"),
        ClassifierTab(id: "BAKING",      label: "Baking",     icon: "birthday.cake"),
        ClassifierTab(id: "CANNED_GOOD", label: "Canned",     icon: "cylinder"),
        ClassifierTab(id: "NUT_SEED",    label: "Nuts",       icon: "circle.hexagongrid"),
        ClassifierTab(id: "FRESH_HERB",  label: "Herbs",      icon: "leaf.circle"),
        ClassifierTab(id: "SWEETENER",   label: "Sweeteners", icon: "star"),
        ClassifierTab(id: "ALCOHOL",     label: "Alcohol",    icon: "wineglass"),
        ClassifierTab(id: "OTHER_INGR",  label: "Other",      icon: "tray"),
    ]
}

struct SearchView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var cartStore: CartStore

    @State private var query = ""
    @State private var selectedTab: ClassifierTab = ClassifierTab.all[0]
    @State private var results: [KrogerItem] = []
    @State private var isLoading = false
    @State private var errorText: String? = nil

    @State private var pageSize = 50
    @State private var offset = 0
    @State private var isLoadingMore = false
    @State private var hasMore = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                Text("ShopWise")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.top, 6)

                // Search bar
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

                // Classifier tabs — scrollable row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ClassifierTab.all) { tab in
                            ClassifierChip(tab: tab, isSelected: selectedTab == tab) {
                                selectedTab = tab
                                searchItems(reset: true)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 1)
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
                } else if results.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("No results")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            ProductCard(
                                imageURL: item.imageURL,
                                title: item.name,
                                unit: item.size,
                                priceText: item.displayPrice(),
                                onAdd: {
                                    cartStore.add(
                                        id: String(item.productId),
                                        name: item.name,
                                        unit: item.size ?? "",
                                        price: item.minPrice ?? 0
                                    )
                                }
                            )
                            .onAppear {
                                if index == results.count - 1 {
                                    searchItems(reset: false)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .appToolbar()
        .onChange(of: query) { _, _ in
            searchItems(reset: true)
        }
        .task {
            searchItems(reset: true)
        }
    }

    // MARK: - Fetch
    // Filtering is done server-side by passing classifier to Supabase —
    // no client-side filter needed at all.
    private func searchItems(reset: Bool = true) {
        if isLoadingMore { return }

        if reset {
            offset = 0
            results = []
            hasMore = true
        } else {
            if !hasMore { return }
        }

        if reset { isLoading = true } else { isLoadingMore = true }
        errorText = nil

        Task {
            do {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                let newItems = try await auth.fetchKrogerItems(
                    search: trimmed.isEmpty ? nil : trimmed,
                    classifier: selectedTab.id == "All" ? nil : selectedTab.id,
                    limit: pageSize,
                    offset: offset
                )

                await MainActor.run {
                    results.append(contentsOf: newItems)
                    offset += newItems.count
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

// MARK: - Classifier chip

struct ClassifierChip: View {
    let tab: ClassifierTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(tab.label)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(isSelected ? Color.blue : Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Product card

struct ProductCard: View {
    let imageURL: URL?
    let title: String
    let unit: String?
    let priceText: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(width: 74, height: 74)
                case .success(let image):
                    image.resizable().scaledToFill()
                        .frame(width: 74, height: 74).clipped()
                case .failure:
                    Image(systemName: "photo")
                        .frame(width: 74, height: 74).foregroundStyle(.secondary)
                @unknown default:
                    EmptyView().frame(width: 74, height: 74)
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(priceText)
                    .font(.headline)
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
        .padding(14)
        .background(Color(.systemGray6).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
