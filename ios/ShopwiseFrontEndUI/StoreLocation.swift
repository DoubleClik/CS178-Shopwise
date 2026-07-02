import Foundation
import CoreLocation

struct StoreLocation: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String?
    let chain: String?

    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        chain: String? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.chain = chain
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
