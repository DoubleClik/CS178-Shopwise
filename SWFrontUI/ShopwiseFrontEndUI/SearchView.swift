//import SwiftUI
import UIKit
//
//// MARK: - Classifier tab definition
//struct ClassifierTab: Identifiable, Equatable {
//    let id: String       // actual DB value or "All"
//    let label: String    // display name
//    let icon: String     // SF Symbol
//
//    static let all: [ClassifierTab] = [
//        ClassifierTab(id: "All",         label: "All",        icon: "square.grid.2x2"),
//        ClassifierTab(id: "PRODUCE",     label: "Produce",    icon: "leaf"),
//        ClassifierTab(id: "PROTEIN",     label: "Protein",    icon: "fork.knife"),
//        ClassifierTab(id: "DAIRY",       label: "Dairy",      icon: "drop"),
//        ClassifierTab(id: "GRAIN",       label: "Grain",      icon: "bag"),
//        ClassifierTab(id: "SPICE",       label: "Spices",     icon: "sparkles"),
//        ClassifierTab(id: "CONDIMENT",   label: "Condiments", icon: "mug"),
//        ClassifierTab(id: "OIL_FAT",     label: "Oils",       icon: "flame"),
//        ClassifierTab(id: "BAKING",      label: "Baking",     icon: "birthday.cake"),
//        ClassifierTab(id: "CANNED_GOOD", label: "Canned",     icon: "cylinder"),
//        ClassifierTab(id: "NUT_SEED",    label: "Nuts",       icon: "circle.hexagongrid"),
//        ClassifierTab(id: "FRESH_HERB",  label: "Herbs",      icon: "leaf.circle"),
//        ClassifierTab(id: "SWEETENER",   label: "Sweeteners", icon: "star"),
//        ClassifierTab(id: "ALCOHOL",     label: "Alcohol",    icon: "wineglass"),
//        ClassifierTab(id: "OTHER_INGR",  label: "Other",      icon: "tray"),
//    ]
//}
//
//struct SearchView: View {
//    @EnvironmentObject private var auth: AuthManager
//    @EnvironmentObject private var cartStore: CartStore
//
//    @State private var query = ""
//    @State private var selectedTab: ClassifierTab = ClassifierTab.all[0]
//    @State private var results: [KrogerItem] = []
//    @State private var isLoading = false
//    @State private var errorText: String? = nil
//
//    @State private var pageSize = 50
//    @State private var offset = 0
//    @State private var isLoadingMore = false
//    @State private var hasMore = true
//
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 14) {
//
//                Text("ShopWise")
//                    .font(.system(size: 34, weight: .bold))
//                    .padding(.top, 6)
//                    .padding(.bottom, 4)
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
//                .padding(.bottom, 4)
//
//                // Classifier tabs — scrollable row
//                ScrollView(.horizontal, showsIndicators: false) {
//                    HStack(spacing: 10) {
//                        ForEach(ClassifierTab.all) { tab in
//                            ClassifierChip(tab: tab, isSelected: selectedTab == tab) {
//                                selectedTab = tab
//                                searchItems(reset: true)
//                            }
//                        }
//                    }
//                    .padding(.vertical, 2)
//                    .padding(.horizontal, 1)
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
//                } else if results.isEmpty {
//                    HStack {
//                        Spacer()
//                        VStack(spacing: 8) {
//                            Image(systemName: "magnifyingglass")
//                                .font(.system(size: 36))
//                                .foregroundStyle(.tertiary)
//                            Text("No results")
//                                .foregroundStyle(.secondary)
//                        }
//                        Spacer()
//                    }
//                    .padding(.top, 40)
//                } else {
//                    LazyVStack(spacing: 14) {
//                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
//                            ProductCard(
//                                imageURL: item.imageURL,
//                                title: item.name,
//                                unit: item.size,
//                                priceText: item.displayPrice(),
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
//                                if index == results.count - 1 {
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
//    // MARK: - Fetch
//    // Filtering is done server-side by passing classifier to Supabase —
//    // no client-side filter needed at all.
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
//                    classifier: selectedTab.id == "All" ? nil : selectedTab.id,
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
//// MARK: - Classifier chip
//
//struct ClassifierChip: View {
//    let tab: ClassifierTab
//    let isSelected: Bool
//    let action: () -> Void
//
//    var body: some View {
//        Button(action: action) {
//            HStack(spacing: 6) {
//                Image(systemName: tab.icon)
//                    .font(.system(size: 12, weight: .medium))
//                Text(tab.label)
//                    .font(.subheadline.weight(.semibold))
//            }
//            .padding(.horizontal, 14)
//            .padding(.vertical, 8)
//            .background(isSelected ? Color.blue.opacity(0.15) : Color(.systemGray6))
//            .foregroundStyle(isSelected ? Color.blue : Color.primary)
//            .clipShape(Capsule())
//            .overlay(
//                Capsule()
//                    .strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
//            )
//        }
//        .buttonStyle(.plain)
//    }
//}
//
//// MARK: - Product card
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
//        .background(
//            RoundedRectangle(cornerRadius: 18, style: .continuous)
//                .fill(Color(.systemGray6).opacity(0.65))
//        )
//        .overlay(
//            RoundedRectangle(cornerRadius: 18, style: .continuous)
//                .stroke(Color.black.opacity(0.04), lineWidth: 1)
//        )
//        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
//    }
//}

import SwiftUI

// MARK: - Store tab definition

struct StoreTab: Identifiable, Equatable {
    let id: String       // store name or "All"
    let label: String
    let icon: String

    static let all: [StoreTab] = [
        StoreTab(id: "All",                    label: "All",        icon: "square.grid.2x2"),
        StoreTab(id: "Walmart",                label: "Walmart",    icon: "cart.fill"),
        StoreTab(id: "Ralphs",                 label: "Ralphs",     icon: "storefront.fill"),
        StoreTab(id: "Stater Bros.",           label: "Stater Bros",icon: "basket.fill"),
        StoreTab(id: "Food4Less",              label: "Food4Less",  icon: "tag.fill"),
        StoreTab(id: "Sprouts Farmers Market", label: "Sprouts",    icon: "leaf.fill"),
        StoreTab(id: "ALDI",                   label: "ALDI",       icon: "dollarsign.circle.fill"),
        StoreTab(id: "Costco",                 label: "Costco",     icon: "shippingbox.fill"),
        StoreTab(id: "99 Ranch Market",        label: "99 Ranch",   icon: "globe.asia.australia.fill"),
        StoreTab(id: "Smart & Final",          label: "Smart & Final", icon: "bag.fill"),
        StoreTab(id: "Target",                 label: "Target",     icon: "scope"),
    ]
}

// MARK: - SearchView

struct SearchView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var cartStore: CartStore

    @State private var query = ""
    @State private var selectedTab: StoreTab = StoreTab.all[0]
    @State private var results: [ScrapedIngredient] = []
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

                // Store tabs — scrollable row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(StoreTab.all) { tab in
                            StoreChip(tab: tab, isSelected: selectedTab == tab) {
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
                                unit: item.quantity,
                                priceText: item.displayPrice,       // var not func
                                storeName: selectedTab.id == "All" ? item.store : nil,
                                onAdd: {
                                    cartStore.add(
                                        id: item.id,
                                        name: item.name,
                                        unit: item.quantity ?? "",
                                        price: item.price ?? 0
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

    // MARK: - Fetch from scraped_ingredients

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
                let newItems = try await auth.searchScrapedIngredients(
                    query: trimmed,
                    store: selectedTab.id == "All" ? nil : selectedTab.id,
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

// MARK: - Store chip

struct StoreChip: View {
    let tab: StoreTab
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
    var storeName: String? = nil   // shown in "All" tab so user knows which store
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

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                if let storeName {
                    HStack(spacing: 4) {
                        if let asset = storeLogoAsset(for: storeName),
                           UIImage(named: asset) != nil {
                            Image(asset)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 50)
                        } else {
                            Text(storeName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                    }
                }

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
