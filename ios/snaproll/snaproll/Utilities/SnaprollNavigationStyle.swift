import SwiftUI

private struct SnaprollScreenNavigationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    func snaprollScreenNavigation() -> some View {
        modifier(SnaprollScreenNavigationModifier())
    }
}
