import SwiftUI

@main
struct SnaprollApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(SnaprollAppDelegate.self) private var appDelegate
    #endif
    private let developmentAuthSettings: DevelopmentAuthSettings
    private let v2Dependencies: V2DependencyContainer
    private let v2SessionStore: V2SessionStore
    private let inviteRoutingCoordinator: V2InviteRoutingCoordinator

    init() {
        let identityStore = DevelopmentAuthIdentityStore(
            defaultIdentity: AppConfig.V2.developmentIdentity
        )
        let developmentAuthSettings = DevelopmentAuthSettings(identityStore: identityStore)
        let dependencies = V2DependencyContainer.live(
            developmentAuthIdentityProvider: identityStore
        )
        self.developmentAuthSettings = developmentAuthSettings
        self.v2Dependencies = dependencies
        self.v2SessionStore = V2SessionStore(authRepository: dependencies.authRepository)
        self.inviteRoutingCoordinator = V2InviteRoutingCoordinator()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if AppConfig.V2.isSessionBootstrapEnabled {
                    V2BootstrapEntryView(
                        sessionStore: v2SessionStore,
                        dependencies: v2Dependencies,
                        developmentAuthSettings: developmentAuthSettings,
                        inviteRoutingCoordinator: inviteRoutingCoordinator
                    )
                } else {
                    HomeView()
                }
            }
            .onOpenURL { url in
                inviteRoutingCoordinator.handleIncomingURL(url)
            }
        }
    }
}
