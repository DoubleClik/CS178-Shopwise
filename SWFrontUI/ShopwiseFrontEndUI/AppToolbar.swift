import SwiftUI

struct AppToolbar: ViewModifier {
    @State private var showAccount = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("ShopwiseLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("ShopWise")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAccount = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showAccount) {
                NavigationStack {
                    ProfileView()
                }
            }
    }
}

extension View {
    func appToolbar() -> some View {
        self.modifier(AppToolbar())
    }
}

extension View {
    @ViewBuilder
    func when(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
