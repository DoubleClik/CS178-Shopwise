import SwiftUI
import Combine

final class CartStore: ObservableObject {
    @Published var itemCount: Int = 0
}
