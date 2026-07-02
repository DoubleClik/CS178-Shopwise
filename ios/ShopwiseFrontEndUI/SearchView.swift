import UIKit
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
    @State private var expandedItemId: String? = nil

    @State private var pageSize = 50
    @State private var offset = 0
    @State private var isLoadingMore = false
    @State private var hasMore = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                /*Text("ShopWise")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.top, 6)
                    .padding(.bottom, 4)*/

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
                                isExpanded: expandedItemId == item.id,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedItemId == item.id {
                                            expandedItemId = nil
                                        } else {
                                            expandedItemId = item.id
                                        }
                                    }
                                },
                                onAdd: {
                                    let fallbackStore = selectedTab.id == "All" ? nil : selectedTab.id
                                    cartStore.add(
                                        id: item.id,
                                        name: item.name,
                                        unit: item.quantity ?? "",
                                        price: item.price ?? 0,
                                        storeName: item.store.isEmpty ? fallbackStore : item.store
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
            .background(isSelected ? Theme.primary.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(isSelected ? Theme.primary : Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Theme.primary.opacity(0.4) : Color.clear, lineWidth: 1)
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
    let isExpanded: Bool
    let onToggle: () -> Void
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
                    .lineLimit(isExpanded ? nil : 2)

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
                .background(Theme.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .padding(14)
        .background(Color(.systemGray6).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
