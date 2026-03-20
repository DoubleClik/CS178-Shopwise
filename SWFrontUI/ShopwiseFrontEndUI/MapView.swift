import SwiftUI
import UIKit
import MapKit
import CoreLocation

// MARK: - Store model

struct StoreAnnotation: Identifiable {
    let id: String
    let name: String
    let chain: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let locationId: String?

    /// Name of the image asset in Assets.xcassets
    var logoAsset: String {
        switch chain {
        case "Walmart":       return "logo_walmart"
        case "Ralphs":        return "logo_ralphs"
        case "Food 4 Less":   return "logo_food4less"
        case "Stater Bros.":  return "logo_stater"
        case "Sprouts":       return "logo_sprouts"
        case "ALDI":          return "logo_aldi"
        case "Smart & Final": return "logo_smartfinal"
        case "99 Ranch":      return "logo_99ranch"
        default:              return ""
        }
    }

    var markerTint: Color {
        switch chain {
        case "Walmart":       return .blue
        case "Ralphs", "Food 4 Less": return .orange
        case "Stater Bros.":  return .red
        case "Sprouts":       return .green
        case "ALDI":          return .purple
        case "Smart & Final": return .cyan
        case "99 Ranch":      return Color(red: 0.9, green: 0.3, blue: 0.1)
        default:              return .gray
        }
    }

    var icon: String {
        switch chain {
        case "Walmart":       return "cart.fill"
        case "Sprouts":       return "leaf.fill"
        case "99 Ranch":      return "globe.asia.australia.fill"
        case "ALDI":          return "dollarsign.circle.fill"
        case "Smart & Final": return "bag.fill"
        default:              return "storefront.fill"
        }
    }
}

// MARK: - Hardcoded stores near UCR (Kroger-family + Walmart)
// Kroger stores are hardcoded since kroger_locations table needs to be populated first.
// Ralphs and Food 4 Less are both Kroger-owned brands in SoCal.

// MARK: - Ralphs / Food 4 Less (Kroger family)
private let krogerStoresNearUCR: [StoreAnnotation] = [
    StoreAnnotation(id: "ralphs_university", name: "Ralphs", chain: "Ralphs",
                    address: "1520 University Ave, Riverside, CA 92507",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9738, longitude: -117.3456), locationId: nil),
    StoreAnnotation(id: "food4less_university", name: "Food 4 Less", chain: "Food 4 Less",
                    address: "1275 University Ave, Riverside, CA 92507",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9718, longitude: -117.3462), locationId: nil),
    StoreAnnotation(id: "ralphs_magnolia", name: "Ralphs", chain: "Ralphs",
                    address: "6225 Magnolia Ave, Riverside, CA 92506",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9524, longitude: -117.3698), locationId: nil),
    StoreAnnotation(id: "ralphs_arlington", name: "Ralphs", chain: "Ralphs",
                    address: "5905 Arlington Ave, Riverside, CA 92504",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9989, longitude: -117.3929), locationId: nil),
    StoreAnnotation(id: "food4less_merrill", name: "Food 4 Less", chain: "Food 4 Less",
                    address: "3750 Merrill Ave, Riverside, CA 92506",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9292, longitude: -117.3812), locationId: nil),
    StoreAnnotation(id: "ralphs_central", name: "Ralphs", chain: "Ralphs",
                    address: "3650 Central Ave, Riverside, CA 92506",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9453, longitude: -117.3957), locationId: nil),
    StoreAnnotation(id: "ralphs_magnolia2", name: "Ralphs", chain: "Ralphs",
                    address: "12061 Magnolia Ave, Riverside, CA 92503",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9993, longitude: -117.4229), locationId: nil),
]

// MARK: - Stater Bros.
private let staterBrosStoresNearUCR: [StoreAnnotation] = [
    StoreAnnotation(id: "stater_1", name: "Stater Bros.", chain: "Stater Bros.",
                    address: "2995 Iowa Ave, Riverside, CA 92507",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9859162, longitude: -117.341186), locationId: nil),
    StoreAnnotation(id: "stater_2", name: "Stater Bros.", chain: "Stater Bros.",
                    address: "4488 Magnolia Ave, Riverside, CA 92501",
                    coordinate: CLLocationCoordinate2D(latitude: 33.934523, longitude: -117.3865065), locationId: nil),
    StoreAnnotation(id: "stater_3", name: "Stater Bros.", chain: "Stater Bros.",
                    address: "315 E Alessandro Blvd, Riverside, CA 92508",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9142125, longitude: -117.3281308), locationId: nil),
    StoreAnnotation(id: "stater_4", name: "Stater Bros.", chain: "Stater Bros.",
                    address: "12270 Sycamore Canyon Rd, Riverside, CA 92503",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9483928, longitude: -117.2622614), locationId: nil),
    StoreAnnotation(id: "stater_5", name: "Stater Bros.", chain: "Stater Bros.",
                    address: "4680 La Sierra Ave, Riverside, CA 92505",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9976104, longitude: -117.4055226), locationId: nil),
    StoreAnnotation(id: "stater_6", name: "Stater Bros.", chain: "Stater Bros.",
                    address: "2995 Iowa Ave, Riverside, CA 92507",
                    coordinate: CLLocationCoordinate2D(latitude: 34.0327531, longitude: -117.3203453), locationId: nil),
]

// MARK: - Sprouts Farmers Market
private let sproutsStoresNearUCR: [StoreAnnotation] = [
    StoreAnnotation(id: "sprouts_1", name: "Sprouts Farmers Market", chain: "Sprouts",
                    address: "475 E Alessandro Blvd, Riverside, CA 92508",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9139385, longitude: -117.3233031), locationId: nil),
    StoreAnnotation(id: "sprouts_2", name: "Sprouts Farmers Market", chain: "Sprouts",
                    address: "12630 Day St, Moreno Valley, CA 92553",
                    coordinate: CLLocationCoordinate2D(latitude: 33.942023, longitude: -117.242369), locationId: nil),
]

// MARK: - ALDI
private let aldiStoresNearUCR: [StoreAnnotation] = [
    StoreAnnotation(id: "aldi_1", name: "ALDI", chain: "ALDI",
                    address: "3750 Tyler St, Riverside, CA 92503",
                    coordinate: CLLocationCoordinate2D(latitude: 33.936734, longitude: -117.276131), locationId: nil),
    StoreAnnotation(id: "aldi_2", name: "ALDI", chain: "ALDI",
                    address: "13460 Perris Blvd, Moreno Valley, CA 92553",
                    coordinate: CLLocationCoordinate2D(latitude: 33.910493, longitude: -117.461808), locationId: nil),
    StoreAnnotation(id: "aldi_3", name: "ALDI", chain: "ALDI",
                    address: "1290 W Colton Ave, Redlands, CA 92374",
                    coordinate: CLLocationCoordinate2D(latitude: 34.064855, longitude: -117.272675), locationId: nil),
]

// MARK: - Smart & Final
private let smartFinalStoresNearUCR: [StoreAnnotation] = [
    StoreAnnotation(id: "smartfinal_1", name: "Smart & Final", chain: "Smart & Final",
                    address: "5202 Arlington Ave, Riverside, CA 92504",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9444932, longitude: -117.4159), locationId: nil),
    StoreAnnotation(id: "smartfinal_2", name: "Smart & Final", chain: "Smart & Final",
                    address: "3310 Vine St, Riverside, CA 92507",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9414981, longitude: -117.2803836), locationId: nil),
    StoreAnnotation(id: "smartfinal_3", name: "Smart & Final", chain: "Smart & Final",
                    address: "2744 Canyon Springs Pkwy, Riverside, CA 92507",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9834495, longitude: -117.3650503), locationId: nil),
]

// MARK: - 99 Ranch Market
private let ranchMarketStoresNearUCR: [StoreAnnotation] = [
    StoreAnnotation(id: "ranch_1", name: "99 Ranch Market", chain: "99 Ranch",
                    address: "430 McKinley St, Corona, CA 92879",
                    coordinate: CLLocationCoordinate2D(latitude: 33.8886384, longitude: -117.5218049), locationId: nil),
    StoreAnnotation(id: "ranch_2", name: "99 Ranch Market", chain: "99 Ranch",
                    address: "4956 Hamner Ave, Eastvale, CA 91752",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9988899, longitude: -117.5559616), locationId: nil),
]

private let walmartStoresNearUCR: [StoreAnnotation] = [
    StoreAnnotation(id: "walmart_1", name: "Walmart Supercenter", chain: "Walmart",
                    address: "12721 Moreno Beach Dr, Moreno Valley, CA 92555",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9384322, longitude: -117.2861652), locationId: nil),
    StoreAnnotation(id: "walmart_2", name: "Walmart Supercenter", chain: "Walmart",
                    address: "5200 Van Buren Blvd, Riverside, CA 92503",
                    coordinate: CLLocationCoordinate2D(latitude: 34.0497547, longitude: -117.3065025), locationId: nil),
    StoreAnnotation(id: "walmart_3", name: "Walmart Supercenter", chain: "Walmart",
                    address: "8844 Limonite Ave, Jurupa Valley, CA 92509",
                    coordinate: CLLocationCoordinate2D(latitude: 34.0762367, longitude: -117.3733901), locationId: nil),
    StoreAnnotation(id: "walmart_4", name: "Walmart Supercenter", chain: "Walmart",
                    address: "1290 E Ontario Ave, Corona, CA 92881",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9371558, longitude: -117.4554553), locationId: nil),
    StoreAnnotation(id: "walmart_5", name: "Walmart Supercenter", chain: "Walmart",
                    address: "479 N McKinley St, Corona, CA 92879",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9739612, longitude: -117.5904619), locationId: nil),
    StoreAnnotation(id: "walmart_6", name: "Walmart Supercenter", chain: "Walmart",
                    address: "1366 S Riverside Ave, Rialto, CA 92376",
                    coordinate: CLLocationCoordinate2D(latitude: 33.8061034, longitude: -117.2295603), locationId: nil),
    StoreAnnotation(id: "walmart_7", name: "Walmart Supercenter", chain: "Walmart",
                    address: "725 N Tippecanoe Ave, San Bernardino, CA 92410",
                    coordinate: CLLocationCoordinate2D(latitude: 34.1378079, longitude: -117.1946666), locationId: nil),
]

// MARK: - MapView

struct MapView: View {
    @EnvironmentObject private var auth: AuthManager
    @StateObject private var locationManager = LocationManager()

    private let ucrCoordinate = CLLocationCoordinate2D(latitude: 33.9737, longitude: -117.3281)

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.9737, longitude: -117.3281),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    )

    @State private var krogerStores: [StoreAnnotation] = []
    @State private var isLoadingStores = false
    @State private var selectedStore: StoreAnnotation? = nil
    @State private var errorText: String? = nil

    // Collapsible section state
    @State private var krogerExpanded    = true
    @State private var walmartExpanded   = false
    @State private var staterExpanded    = false
    @State private var sproutsExpanded   = false
    @State private var aldiExpanded      = false
    @State private var smartFinalExpanded = false
    @State private var ranchExpanded     = false

    private var allStores: [StoreAnnotation] { krogerStoresNearUCR + walmartStoresNearUCR + staterBrosStoresNearUCR + sproutsStoresNearUCR + aldiStoresNearUCR + smartFinalStoresNearUCR + ranchMarketStoresNearUCR }
    private var centerCoordinate: CLLocationCoordinate2D { locationManager.userLocation ?? ucrCoordinate }

    var body: some View {
        List {
            mapSection
            if let store = selectedStore { selectedStoreSection(store) }
            krogerSection
            walmartSection
            staterBrosSection
            sproutsSection
            aldiSection
            smartFinalSection
            ranchMarketSection
            locationSection
        }
        .listStyle(.plain)
        .navigationTitle("ShopWise")
        .navigationBarTitleDisplayMode(.inline)
        .appToolbar()
        .task { }  // kroger stores are hardcoded — swap for live fetch once kroger_locations is populated
        .onAppear { locationManager.requestPermission() }
        .onChange(of: locationManager.userLocation?.latitude ?? 0) { _, lat in
            guard lat != 0 else { return }
            centerOnUser()
        }
    }

    // MARK: - Sections (broken out to help type checker)

    private var mapSection: some View {
        Section {
            CardContainer {
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(allStores) { store in
                        Annotation(store.name, coordinate: store.coordinate) {
                            StorePin(store: store, isSelected: selectedStore?.id == store.id)
                                .onTapGesture {
                                    withAnimation { selectedStore = store }
                                    focusOn(store.coordinate)
                                }
                        }
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) { locationButton }
            }
            .listRowInsets(EdgeInsets())
        }
    }

    private var locationButton: some View {
        Button { centerOnUser() } label: {
            Image(systemName: "location.fill")
                .padding(10)
                .background(.regularMaterial)
                .clipShape(Circle())
        }
        .padding(10)
        .disabled(locationManager.userLocation == nil)
    }

    private func selectedStoreSection(_ store: StoreAnnotation) -> some View {
        Section {
            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        let cardAsset = storeLogoAsset(for: store.chain)
                        if let cardAsset, UIImage(named: cardAsset) != nil {
                            Image(cardAsset)
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Image(systemName: store.icon)
                                .font(.title2)
                                .foregroundStyle(store.markerTint)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.name).font(.headline)
                            Text(store.chain).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let dist = distanceText(to: store) {
                            Text(dist)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color(.systemGray6))
                                .clipShape(Capsule())
                        }
                    }
                    if !store.address.isEmpty {
                        Label(store.address, systemImage: "mappin")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button { openInMaps(store) } label: {
                        Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.markerTint)
                }
            }
        }
    }

    private var krogerSection: some View {
        Section {
            DisclosureGroup(isExpanded: $krogerExpanded) {
                ForEach(krogerStoresNearUCR) { store in storeRow(store) }
            } label: {
                sectionHeader(title: "Kroger Stores Nearby", count: krogerStoresNearUCR.count, isExpanded: krogerExpanded)
            }
        }
    }

    private var walmartSection: some View {
        Section {
            DisclosureGroup(isExpanded: $walmartExpanded) {
                ForEach(walmartStoresNearUCR) { store in storeRow(store) }
            } label: {
                sectionHeader(title: "Walmart Stores Nearby", count: walmartStoresNearUCR.count, isExpanded: walmartExpanded)
            }
        }
    }

    private var staterBrosSection: some View {
        Section {
            DisclosureGroup(isExpanded: $staterExpanded) {
                ForEach(staterBrosStoresNearUCR) { store in storeRow(store) }
            } label: {
                sectionHeader(title: "Stater Bros. Stores Nearby", count: staterBrosStoresNearUCR.count, isExpanded: staterExpanded)
            }
        }
    }

    private var sproutsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $sproutsExpanded) {
                ForEach(sproutsStoresNearUCR) { store in storeRow(store) }
            } label: {
                sectionHeader(title: "Sprouts Nearby", count: sproutsStoresNearUCR.count, isExpanded: sproutsExpanded)
            }
        }
    }

    private var aldiSection: some View {
        Section {
            DisclosureGroup(isExpanded: $aldiExpanded) {
                ForEach(aldiStoresNearUCR) { store in storeRow(store) }
            } label: {
                sectionHeader(title: "ALDI Stores Nearby", count: aldiStoresNearUCR.count, isExpanded: aldiExpanded)
            }
        }
    }

    private var smartFinalSection: some View {
        Section {
            DisclosureGroup(isExpanded: $smartFinalExpanded) {
                ForEach(smartFinalStoresNearUCR) { store in storeRow(store) }
            } label: {
                sectionHeader(title: "Smart & Final Nearby", count: smartFinalStoresNearUCR.count, isExpanded: smartFinalExpanded)
            }
        }
    }

    private var ranchMarketSection: some View {
        Section {
            DisclosureGroup(isExpanded: $ranchExpanded) {
                ForEach(ranchMarketStoresNearUCR) { store in storeRow(store) }
            } label: {
                sectionHeader(title: "99 Ranch Market Nearby", count: ranchMarketStoresNearUCR.count, isExpanded: ranchExpanded)
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            HStack {
                Text("Permission")
                Spacer()
                Text(locationStatusText).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(title: String, count: Int, isExpanded: Bool) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.8))
                .clipShape(Capsule())
        }
        .contentShape(Rectangle())
    }

    // MARK: - Store row

    private func storeRow(_ store: StoreAnnotation) -> some View {
        Button {
            withAnimation { selectedStore = store }
            focusOn(store.coordinate)
        } label: {
            HStack(spacing: 12) {
                let rowAsset = storeLogoAsset(for: store.chain)
                if let rowAsset, UIImage(named: rowAsset) != nil {
                    Image(rowAsset)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .frame(width: 38, height: 38)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: store.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(store.markerTint)
                        .frame(width: 38, height: 38)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.name).font(.subheadline.weight(.medium))
                    if !store.address.isEmpty {
                        Text(store.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let dist = distanceText(to: store) {
                    Text(dist).font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data loading

    @MainActor
    private func loadKrogerStores() async {
        guard !isLoadingStores else { return }
        isLoadingStores = true
        errorText = nil
        do {
            let fetched = try await auth.fetchNearbyKrogerStores(
                near: centerCoordinate, radiusDegrees: 0.2
            )
            krogerStores = fetched.compactMap { store -> StoreAnnotation? in
                guard let coord = store.coordinate else { return nil }
                return StoreAnnotation(
                    id: "kroger_\(store.locationId)",
                    name: store.displayName,
                    chain: store.chain ?? "Kroger",
                    address: store.displayAddress,
                    coordinate: coord,
                    locationId: String(store.locationId)
                )
            }
        } catch {
            krogerStores = []
        }
        isLoadingStores = false
    }

    // MARK: - Helpers

    private func focusOn(_ coordinate: CLLocationCoordinate2D) {
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
        }
    }

    private func centerOnUser() {
        guard let loc = locationManager.userLocation else { return }
        focusOn(loc)
    }

    private func distanceText(to store: StoreAnnotation) -> String? {
        guard let userLoc = locationManager.userLocation else { return nil }
        let user = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
        let dest = CLLocation(latitude: store.coordinate.latitude, longitude: store.coordinate.longitude)
        let miles = user.distance(from: dest) / 1609.34
        return String(format: "%.1f mi", miles)
    }

    private func openInMaps(_ store: StoreAnnotation) {
        // Use Maps URL scheme — avoids MKPlacemark deprecation entirely
        let query = store.address.isEmpty
            ? "\(store.coordinate.latitude),\(store.coordinate.longitude)"
            : store.address
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "maps://?daddr=\(encoded)&dirflg=d"
        if let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .notDetermined: return "Not Requested"
        case .restricted:    return "Restricted"
        case .denied:        return "Denied"
        case .authorizedAlways, .authorizedWhenInUse: return "Allowed"
        @unknown default:    return "Unknown"
        }
    }
}

// MARK: - Store pin

struct StorePin: View {
    let store: StoreAnnotation
    let isSelected: Bool

    private let size: CGFloat = 40
    private let selectedSize: CGFloat = 52

    var body: some View {
        let pinSize = isSelected ? selectedSize : size

        ZStack {
            // White circle background
            Circle()
                .fill(.white)
                .frame(width: pinSize, height: pinSize)
                .shadow(color: store.markerTint.opacity(0.4),
                        radius: isSelected ? 8 : 3,
                        x: 0, y: 2)
                .overlay(
                    Circle()
                        .strokeBorder(store.markerTint,
                                      lineWidth: isSelected ? 3 : 2)
                )

            // Logo image if asset exists, otherwise SF Symbol fallback
            let asset = storeLogoAsset(for: store.chain) ?? store.logoAsset
            if UIImage(named: asset) != nil {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: pinSize * 0.65, height: pinSize * 0.65)
                    .clipShape(Circle())
            } else {
                Image(systemName: store.icon)
                    .font(.system(size: isSelected ? 20 : 15, weight: .semibold))
                    .foregroundStyle(store.markerTint)
            }
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
