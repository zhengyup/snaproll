import SwiftUI

@main
struct SnaprollApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(SnaprollAppDelegate.self) private var appDelegate
    #endif
    private let v2Dependencies: V2DependencyContainer
    private let v2SessionStore: V2SessionStore

    init() {
        let dependencies = V2DependencyContainer.live()
        self.v2Dependencies = dependencies
        self.v2SessionStore = V2SessionStore(authRepository: dependencies.authRepository)
    }

    var body: some Scene {
        WindowGroup {
            if AppConfig.V2.isSessionBootstrapEnabled {
                V2BootstrapEntryView(sessionStore: v2SessionStore)
            } else {
                HomeView()
            }
        }
    }
}
