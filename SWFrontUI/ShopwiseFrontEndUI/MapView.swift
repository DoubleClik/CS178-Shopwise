import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @StateObject private var locationManager = LocationManager()

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.978194, longitude: -117.367861),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    @State private var stores: [StoreLocation] = [
        StoreLocation(
            id: "store_walmart",
            name: "Walmart Supercenter",
            latitude: 33.988194,
            longitude: -117.361861,
            address: nil,
            chain: "Walmart"
        ),
        StoreLocation(
            id: "store_ralphs",
            name: "Ralphs",
            latitude: 33.970194,
            longitude: -117.363861,
            address: nil,
            chain: "Ralphs"
        )
    ]

    var body: some View {
        List {
            Section {
                CardContainer {
                    Map(position: $position) {
                        UserAnnotation()

                        ForEach(stores) { store in
                            Marker(store.name, coordinate: store.coordinate)
                        }
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .listRowInsets(EdgeInsets())
            }

            Section("Nearby Grocery Stores") {
                ForEach(stores) { store in
                    Button {
                        position = .region(
                            MKCoordinateRegion(
                                center: store.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                            )
                        )
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill")

                            VStack(alignment: .leading) {
                                Text(store.name)
                                Text(store.chain ?? "Store")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Location") {
                Button {
                    centerOnUser()
                } label: {
                    Label("Center on Me", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(locationManager.userLocation == nil)

                HStack {
                    Text("Permission")
                    Spacer()
                    Text(locationStatusText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("ShopWise")
        .appToolbar()
        .onAppear {
            locationManager.requestPermission()
        }
        .onChange(of: locationManager.userLocation?.latitude ?? 0) { _, newLatitude in
            guard newLatitude != 0 else { return }
            centerOnUser()
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return "Not Requested"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways:
            return "Allowed"
        case .authorizedWhenInUse:
            return "Allowed"
        @unknown default:
            return "Unknown"
        }
    }

    private func centerOnUser() {
        guard let user = locationManager.userLocation else { return }

        position = .region(
            MKCoordinateRegion(
                center: user,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }
}
