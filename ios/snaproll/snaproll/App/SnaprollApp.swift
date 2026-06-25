import SwiftUI

@main
struct SnaprollApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(SnaprollAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
