import Foundation

struct V2DependencyContainer {
    let authRepository: any AuthRepository
    let rollRepository: any RollRepository
    let participantRepository: any ParticipantRepository
    let exposureRepository: any ExposureRepository
    let exposureMirrorStore: any ExposureMirrorStore
    let exposureAssetStorageRepository: any ExposureAssetStorageRepository
    let inviteRepository: any InviteRepository
    let invitePreviewRepository: any InvitePreviewRepository
    let photoStorageService: PhotoStorageService
    let exposureSyncRunner: any ExposureSyncRunning
    let exposureReconciliationCoordinator: any ExposureReconciling
    let pendingExposureRecoveryCoordinator: any PendingExposureRecovering

    static func live(
        authenticationMode: V2AuthenticationMode = AppConfig.V2.authenticationMode,
        developmentAuthIdentityProvider: (any DevelopmentAuthIdentityProviding)? = nil
    ) -> V2DependencyContainer {
        let clientProvider = V2SupabaseClientProvider()
        let authRepository: any AuthRepository

        switch authenticationMode {
        case .standard:
            authRepository = SupabaseAuthRepository(clientProvider: clientProvider)
        case .development(let identity):
            authRepository = DevelopmentAuthRepository(
                clientProvider: clientProvider,
                identityProvider: developmentAuthIdentityProvider ?? FixedDevelopmentAuthIdentityProvider(identity: identity),
                sessionStore: UserDefaultsDevelopmentAuthSessionStore()
            )
        }

        let rollRepository = SupabaseRollRepository(clientProvider: clientProvider)
        let participantRepository = SupabaseParticipantRepository(clientProvider: clientProvider)
        let exposureRepository = SupabaseExposureRepository(clientProvider: clientProvider)
        let exposureMirrorStore = FileBackedExposureMirrorStore()
        let photoStorageService = PhotoStorageService()
        let storageRepository = SupabaseExposureAssetStorageRepository(clientProvider: clientProvider)
        let uploadPipeline = V2ExposureUploadPipeline(
            exposureMirrorStore: exposureMirrorStore,
            photoStorageService: photoStorageService,
            storageRepository: storageRepository
        )
        let metadataPipeline = V2ExposureMetadataCompletionPipeline(
            exposureMirrorStore: exposureMirrorStore,
            exposureRepository: exposureRepository
        )
        let exposureSyncRunner = V2ExposureSyncRunner(
            exposureMirrorStore: exposureMirrorStore,
            uploadStage: uploadPipeline,
            metadataStage: metadataPipeline,
            authRepository: authRepository
        )
        let exposureReconciliationCoordinator = V2ExposureReconciliationCoordinator(
            authRepository: authRepository,
            rollRepository: rollRepository,
            participantRepository: participantRepository,
            exposureRepository: exposureRepository,
            exposureMirrorStore: exposureMirrorStore,
            photoStorageService: photoStorageService
        )
        let pendingExposureRecoveryCoordinator = V2PendingExposureRecoveryCoordinator(
            authRepository: authRepository,
            rollRepository: rollRepository,
            participantRepository: participantRepository,
            exposureMirrorStore: exposureMirrorStore,
            syncRunner: exposureSyncRunner,
            reconciler: exposureReconciliationCoordinator
        )

        return V2DependencyContainer(
            authRepository: authRepository,
            rollRepository: rollRepository,
            participantRepository: participantRepository,
            exposureRepository: exposureRepository,
            exposureMirrorStore: exposureMirrorStore,
            exposureAssetStorageRepository: storageRepository,
            inviteRepository: SupabaseInviteRepository(clientProvider: clientProvider),
            invitePreviewRepository: SupabaseInvitePreviewRepository(clientProvider: clientProvider),
            photoStorageService: photoStorageService,
            exposureSyncRunner: exposureSyncRunner,
            exposureReconciliationCoordinator: exposureReconciliationCoordinator,
            pendingExposureRecoveryCoordinator: pendingExposureRecoveryCoordinator
        )
    }
}
