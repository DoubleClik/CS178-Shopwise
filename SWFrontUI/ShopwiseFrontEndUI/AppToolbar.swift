import SwiftUI

struct AppToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
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
