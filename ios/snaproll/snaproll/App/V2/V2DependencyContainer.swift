import Foundation

struct V2DependencyContainer {
    let authRepository: any AuthRepository
    let rollRepository: any RollRepository
    let participantRepository: any ParticipantRepository
    let exposureRepository: any ExposureRepository
    let inviteRepository: any InviteRepository

    static func live(
        authenticationMode: V2AuthenticationMode = AppConfig.V2.authenticationMode
    ) -> V2DependencyContainer {
        let clientProvider = V2SupabaseClientProvider()
        let authRepository: any AuthRepository

        switch authenticationMode {
        case .standard:
            authRepository = SupabaseAuthRepository(clientProvider: clientProvider)
        case .development(let identity):
            authRepository = DevelopmentAuthRepository(
                clientProvider: clientProvider,
                identityProvider: FixedDevelopmentAuthIdentityProvider(identity: identity),
                sessionStore: UserDefaultsDevelopmentAuthSessionStore()
            )
        }

        return V2DependencyContainer(
            authRepository: authRepository,
            rollRepository: SupabaseRollRepository(clientProvider: clientProvider),
            participantRepository: SupabaseParticipantRepository(clientProvider: clientProvider),
            exposureRepository: SupabaseExposureRepository(clientProvider: clientProvider),
            inviteRepository: SupabaseInviteRepository(clientProvider: clientProvider)
        )
    }
}
