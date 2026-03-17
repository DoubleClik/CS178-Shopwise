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

    var markerTint: Color {
        chain == "Walmart" ? Theme.primary : Theme.secondary
    }
    var icon: String {
        chain == "Walmart" ? "cart.fill" : "storefront.fill"
    }
}

// MARK: - Hardcoded stores near UCR (Kroger-family + Walmart)
// Kroger stores are hardcoded since kroger_locations table needs to be populated first.
// Ralphs and Food 4 Less are both Kroger-owned brands in SoCal.

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

    private var allStores: [StoreAnnotation] { krogerStoresNearUCR + walmartStoresNearUCR }
    private var centerCoordinate: CLLocationCoordinate2D { locationManager.userLocation ?? ucrCoordinate }

    var body: some View {
        List {
            mapSection
            if let store = selectedStore { selectedStoreSection(store) }
            krogerSection
            walmartSection
            locationSection
        }
        .navigationTitle("ShopWise")
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
                        Image(systemName: store.icon)
                            .font(.title2)
                            .foregroundStyle(store.markerTint)
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
        Section("Kroger Stores Nearby") {
            ForEach(krogerStoresNearUCR) { store in storeRow(store) }
        }
    }

    private var walmartSection: some View {
        Section("Walmart Stores Nearby") {
            ForEach(walmartStoresNearUCR) { store in storeRow(store) }
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

    // MARK: - Store row

    private func storeRow(_ store: StoreAnnotation) -> some View {
        Button {
            withAnimation { selectedStore = store }
            focusOn(store.coordinate)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: store.icon)
                    .foregroundStyle(store.markerTint)
                    .frame(width: 28)
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

    var body: some View {
        ZStack {
            Circle()
                .fill(store.markerTint)
                .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                .shadow(radius: isSelected ? 6 : 2)
            Image(systemName: store.icon)
                .font(.system(size: isSelected ? 18 : 14))
                .foregroundStyle(.white)
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
