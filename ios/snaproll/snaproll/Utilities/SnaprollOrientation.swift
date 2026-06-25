import SwiftUI

#if os(iOS)
import UIKit

final class SnaprollAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        SnaprollOrientationController.currentMask
    }
}

enum SnaprollOrientationController {
    static var currentMask: UIInterfaceOrientationMask = .portrait

    static func setPreferredOrientations(_ mask: UIInterfaceOrientationMask) {
        currentMask = mask

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: mask)
        )
    }
}

private struct SnaprollPreferredOrientationsModifier: ViewModifier {
    let mask: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear {
                SnaprollOrientationController.setPreferredOrientations(mask)
            }
    }
}

extension View {
    func snaprollPreferredOrientations(_ mask: UIInterfaceOrientationMask) -> some View {
        modifier(SnaprollPreferredOrientationsModifier(mask: mask))
    }
}
#else
extension View {
    func snaprollPreferredOrientations(_ mask: Int) -> some View {
        self
    }
}
#endif
