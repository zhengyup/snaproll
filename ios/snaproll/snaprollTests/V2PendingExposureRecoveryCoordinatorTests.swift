import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2PendingExposureRecoveryCoordinatorTests {
    @Test
    func localOnlySurvivesRestartAndIsEligibleForUpload() async throws {
        let rollID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        let userID = UUID(uuidString: "90000000-0000-0000-0000-0000000000A1")!
        let exposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000101")!,
            rollID: rollID,
            participantID: userID,
            exposureNumber: 1,
            syncState: .localOnly
        )
        exposure.local_original_path = "/tmp/local-only.jpg"

        let fileURL = temporaryRecoveryStoreURL()
        let initialStore = FileBackedExposureMirrorStore(fileURL: fileURL)
        try await initialStore.saveExposure(exposure)

        let restartedStore = FileBackedExposureMirrorStore(fileURL: fileURL)
        let syncRunner = RecordingRecoverySyncRunner()
        let coordinator = makeCoordinator(
            userID: userID,
            rolls: [makeRecoveryRoll(id: rollID)],
            mirrorStore: restartedStore,
            syncRunner: syncRunner
        )

        await coordinator.recoverPendingWorkForCurrentSession()

        let recovered = try await restartedStore.fetchExposures(forRollID: rollID)
        #expect(await syncRunner.calls == [RecoverySyncCall(rollID: rollID, participantID: nil)])
        #expect(recovered.first?.sync_state == .localOnly)
        #expect(recovered.first?.last_recovery_from_state == V2Domain.ExposureSyncState.localOnly.rawValue)
        #expect(recovered.first?.last_recovery_to_state == V2Domain.ExposureSyncState.localOnly.rawValue)
    }

    @Test
    func uploadingNormalizesToRetryableUploadState() async throws {
        let rollID = UUID(uuidString: "90000000-0000-0000-0000-000000000002")!
        let userID = UUID(uuidString: "90000000-0000-0000-0000-0000000000A2")!
        let exposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000201")!,
            rollID: rollID,
            participantID: userID,
            exposureNumber: 1,
            syncState: .uploading
        )
        exposure.local_original_path = "/tmp/uploading.jpg"

        let store = InMemoryRecoveryMirrorStore(initialExposures: [rollID: [exposure]])
        let syncRunner = RecordingRecoverySyncRunner()
        let coordinator = makeCoordinator(
            userID: userID,
            rolls: [makeRecoveryRoll(id: rollID)],
            mirrorStore: store,
            syncRunner: syncRunner
        )

        await coordinator.recoverPendingWorkForCurrentSession()

        let recovered = try await store.fetchExposures(forRollID: rollID)
        #expect(recovered.first?.sync_state == .localOnly)
        #expect(recovered.first?.last_recovery_from_state == V2Domain.ExposureSyncState.uploading.rawValue)
        #expect(recovered.first?.last_recovery_to_state == V2Domain.ExposureSyncState.localOnly.rawValue)
    }

    @Test
    func metadataPendingPreservesCloudStoragePathAndResumesMetadataOnly() async throws {
        let rollID = UUID(uuidString: "90000000-0000-0000-0000-000000000003")!
        let userID = UUID(uuidString: "90000000-0000-0000-0000-0000000000A3")!
        let exposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000301")!,
            rollID: rollID,
            participantID: userID,
            exposureNumber: 1,
            syncState: .metadataPending
        )
        let cloudPath = exposure.canonicalCloudStoragePath
        exposure.cloud_storage_path = cloudPath
        exposure.upload_jpeg_path = "/tmp/upload-jpeg.jpg"

        let store = InMemoryRecoveryMirrorStore(initialExposures: [rollID: [exposure]])
        let syncRunner = RecordingRecoverySyncRunner()
        let coordinator = makeCoordinator(
            userID: userID,
            rolls: [makeRecoveryRoll(id: rollID)],
            mirrorStore: store,
            syncRunner: syncRunner
        )

        await coordinator.recoverPendingWorkForCurrentSession()

        let recovered = try await store.fetchExposures(forRollID: rollID)
        #expect(recovered.first?.sync_state == .metadataPending)
        #expect(recovered.first?.cloud_storage_path == cloudPath)
        #expect(recovered.first?.last_recovery_to_state == V2Domain.ExposureSyncState.metadataPending.rawValue)
    }

    @Test
    func failedUploadStageResumesUpload() async throws {
        let rollID = UUID(uuidString: "90000000-0000-0000-0000-000000000004")!
        let userID = UUID(uuidString: "90000000-0000-0000-0000-0000000000A4")!
        let exposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000401")!,
            rollID: rollID,
            participantID: userID,
            exposureNumber: 1,
            syncState: .failed
        )
        exposure.local_original_path = "/tmp/failed-upload.jpg"
        exposure.last_error = "Upload failed"

        let store = InMemoryRecoveryMirrorStore(initialExposures: [rollID: [exposure]])
        let syncRunner = RecordingRecoverySyncRunner()
        let coordinator = makeCoordinator(
            userID: userID,
            rolls: [makeRecoveryRoll(id: rollID)],
            mirrorStore: store,
            syncRunner: syncRunner
        )

        await coordinator.recoverPendingWorkForCurrentSession()

        let recovered = try await store.fetchExposures(forRollID: rollID)
        #expect(recovered.first?.sync_state == .localOnly)
        #expect(recovered.first?.last_recovery_to_state == V2Domain.ExposureSyncState.localOnly.rawValue)
    }

    @Test
    func failedMetadataStageResumesMetadataOnly() async throws {
        let rollID = UUID(uuidString: "90000000-0000-0000-0000-000000000005")!
        let userID = UUID(uuidString: "90000000-0000-0000-0000-0000000000A5")!
        let exposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000501")!,
            rollID: rollID,
            participantID: userID,
            exposureNumber: 1,
            syncState: .failed
        )
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
        exposure.last_error = "Metadata failed"

        let store = InMemoryRecoveryMirrorStore(initialExposures: [rollID: [exposure]])
        let syncRunner = RecordingRecoverySyncRunner()
        let coordinator = makeCoordinator(
            userID: userID,
            rolls: [makeRecoveryRoll(id: rollID)],
            mirrorStore: store,
            syncRunner: syncRunner
        )

        await coordinator.recoverPendingWorkForCurrentSession()

        let recovered = try await store.fetchExposures(forRollID: rollID)
        #expect(recovered.first?.sync_state == .metadataPending)
        #expect(recovered.first?.cloud_storage_path == exposure.canonicalCloudStoragePath)
        #expect(recovered.first?.last_recovery_to_state == V2Domain.ExposureSyncState.metadataPending.rawValue)
    }

    @Test
    func syncedAndEmptyAreIgnored() async throws {
        let rollID = UUID(uuidString: "90000000-0000-0000-0000-000000000006")!
        let userID = UUID(uuidString: "90000000-0000-0000-0000-0000000000A6")!
        let emptyExposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000601")!,
            rollID: rollID,
            participantID: userID,
            exposureNumber: 1,
            syncState: .empty
        )
        let syncedExposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000602")!,
            rollID: rollID,
            participantID: userID,
            exposureNumber: 2,
            syncState: .synced
        )
        syncedExposure.cloud_storage_path = syncedExposure.canonicalCloudStoragePath

        let store = InMemoryRecoveryMirrorStore(initialExposures: [rollID: [emptyExposure, syncedExposure]])
        let syncRunner = RecordingRecoverySyncRunner()
        let coordinator = makeCoordinator(
            userID: userID,
            rolls: [makeRecoveryRoll(id: rollID)],
            mirrorStore: store,
            syncRunner: syncRunner
        )

        await coordinator.recoverPendingWorkForCurrentSession()

        #expect(await syncRunner.calls.isEmpty)
        let recovered = try await store.fetchExposures(forRollID: rollID)
        #expect(recovered[0].last_recovered_at == nil)
        #expect(recovered[1].last_recovered_at == nil)
    }

    @Test
    func recoveryIsScopedToCurrentUserAndRoll() async throws {
        let creatorID = UUID(uuidString: "90000000-0000-0000-0000-0000000000A7")!
        let otherUserID = UUID(uuidString: "90000000-0000-0000-0000-0000000000B7")!
        let personalRollID = UUID(uuidString: "90000000-0000-0000-0000-000000000007")!
        let sharedRollID = UUID(uuidString: "90000000-0000-0000-0000-000000000008")!

        let personalExposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000701")!,
            rollID: personalRollID,
            participantID: creatorID,
            exposureNumber: 1,
            syncState: .localOnly
        )
        let sharedExposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000801")!,
            rollID: sharedRollID,
            participantID: otherUserID,
            exposureNumber: 1,
            syncState: .localOnly
        )

        let store = InMemoryRecoveryMirrorStore(initialExposures: [
            personalRollID: [personalExposure],
            sharedRollID: [sharedExposure]
        ])
        let syncRunner = RecordingRecoverySyncRunner()
        let coordinator = makeCoordinator(
            userID: creatorID,
            rolls: [
                makeRecoveryRoll(id: personalRollID, type: .personal),
                makeRecoveryRoll(id: sharedRollID, type: .shared)
            ],
            participantsByRollID: [
                sharedRollID: [
                    makeRecoveryParticipant(id: UUID(), rollID: sharedRollID, userID: otherUserID)
                ]
            ],
            mirrorStore: store,
            syncRunner: syncRunner
        )

        await coordinator.recoverPendingWorkForCurrentSession()

        #expect(await syncRunner.calls == [RecoverySyncCall(rollID: personalRollID, participantID: nil)])
    }

    @Test
    func recoveryFailureDoesNotDeleteLocalOriginalOrCloudPathMetadata() async throws {
        let rollID = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!
        let userID = UUID(uuidString: "90000000-0000-0000-0000-0000000000A8")!
        let exposure = makeRecoveryExposure(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000901")!,
            rollID: rollID,
            participantID: userID,
            exposureNumber: 1,
            syncState: .metadataPending
        )
        exposure.local_original_path = "/tmp/original.jpg"
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath

        let store = InMemoryRecoveryMirrorStore(initialExposures: [rollID: [exposure]])
        let syncRunner = RecordingRecoverySyncRunner(error: V2RepositoryError.network("Offline"))
        let coordinator = makeCoordinator(
            userID: userID,
            rolls: [makeRecoveryRoll(id: rollID)],
            mirrorStore: store,
            syncRunner: syncRunner
        )

        await coordinator.recoverPendingWorkForCurrentSession()

        let recovered = try await store.fetchExposures(forRollID: rollID)
        #expect(recovered.first?.local_original_path == "/tmp/original.jpg")
        #expect(recovered.first?.cloud_storage_path == exposure.canonicalCloudStoragePath)
        #expect(recovered.first?.last_recovery_error == "Offline")
    }
}

@MainActor
private func makeCoordinator(
    userID: UUID,
    rolls: [LocalRoll],
    participantsByRollID: [UUID: [LocalParticipant]] = [:],
    mirrorStore: any ExposureMirrorStore,
    syncRunner: any ExposureSyncRunning
) -> V2PendingExposureRecoveryCoordinator {
    V2PendingExposureRecoveryCoordinator(
        authRepository: FakeRecoveryAuthRepository(userID: userID),
        rollRepository: FakeRecoveryRollRepository(rolls: rolls),
        participantRepository: FakeRecoveryParticipantRepository(participantsByRollID: participantsByRollID),
        exposureMirrorStore: mirrorStore,
        syncRunner: syncRunner
    )
}

@MainActor
private func makeRecoveryRoll(
    id: UUID,
    type: V2Domain.RollType = .personal,
    status: V2Domain.RollStatus = .shooting
) -> LocalRoll {
    LocalRoll(
        id: id,
        title: "Recovery Roll",
        type: type,
        status: status,
        film_stock_id: FilmStock.kodakGold200.rawValue,
        exposures_per_participant: 12,
        creator_id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        created_at: .now,
        started_at: .now,
        ready_to_reveal_at: nil,
        revealed_at: nil,
        last_synced_at: nil
    )
}

@MainActor
private func makeRecoveryExposure(
    id: UUID,
    rollID: UUID,
    participantID: UUID,
    exposureNumber: Int,
    syncState: V2Domain.ExposureSyncState
) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: participantID,
        exposure_number: exposureNumber,
        render_seed: "seed-\(exposureNumber)",
        sync_state: syncState,
        updated_at: .now
    )
}

@MainActor
private func makeRecoveryParticipant(
    id: UUID,
    rollID: UUID,
    userID: UUID
) -> LocalParticipant {
    LocalParticipant(
        id: id,
        roll_id: rollID,
        user_id: userID,
        display_name: "Participant",
        status: .shooting,
        joined_at: .now,
        finished_at: nil
    )
}

private func temporaryRecoveryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("v2-recovery-mirror.json")
}

@MainActor
private final class InMemoryRecoveryMirrorStore: ExposureMirrorStore {
    private var exposuresByRollID: [UUID: [LocalExposure]]

    init(initialExposures: [UUID: [LocalExposure]]) {
        self.exposuresByRollID = initialExposures
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        (exposuresByRollID[rollID] ?? []).sorted { $0.exposure_number < $1.exposure_number }
    }

    func mirrorCloudExposures(_ exposures: [LocalExposure], forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] = exposures
        return exposures
    }

    func saveExposure(_ exposure: LocalExposure) async throws {
        var exposures = exposuresByRollID[exposure.roll_id] ?? []
        if let index = exposures.firstIndex(where: { $0.id == exposure.id }) {
            exposures[index] = exposure
        } else {
            exposures.append(exposure)
        }
        exposuresByRollID[exposure.roll_id] = exposures.sorted { $0.exposure_number < $1.exposure_number }
    }
}

private struct RecoverySyncCall: Equatable, Sendable {
    let rollID: UUID
    let participantID: UUID?
}

private actor RecordingRecoverySyncRunner: ExposureSyncRunning {
    private(set) var calls: [RecoverySyncCall] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func processPendingExposures(forRollID rollID: UUID) async throws -> V2ExposureSyncRunSummary {
        try await processPendingExposures(forRollID: rollID, participantID: nil)
    }

    func processPendingExposures(forRollID rollID: UUID, participantID: UUID?) async throws -> V2ExposureSyncRunSummary {
        calls.append(RecoverySyncCall(rollID: rollID, participantID: participantID))
        if let error {
            throw error
        }

        return V2ExposureSyncRunSummary(
            processedExposureIDs: [],
            syncedExposureIDs: [],
            failedExposureIDs: []
        )
    }
}

private struct FakeRecoveryAuthRepository: AuthRepository {
    let userID: UUID

    func currentSession() async throws -> AuthSession? {
        AuthSession(userID: userID, displayName: "Recovery User")
    }

    func currentUserID() async throws -> UUID? {
        userID
    }

    func signOut() async throws {}
}

private struct FakeRecoveryRollRepository: RollRepository {
    let rolls: [LocalRoll]

    func fetchRoll(id: UUID) async throws -> LocalRoll? {
        rolls.first(where: { $0.id == id })
    }

    func fetchRolls() async throws -> [LocalRoll] {
        rolls
    }

    func fetchAllRolls() async throws -> [LocalRoll] {
        rolls
    }

    func startRoll(id: UUID) async throws {}
    func revealRoll(id: UUID) async throws {}
    func createRoll(
        title: String,
        type: V2Domain.RollType,
        filmStockID: String,
        exposuresPerParticipant: Int,
        participantCap: Int
    ) async throws -> CreateRollResult {
        CreateRollResult(rollID: UUID(), inviteToken: nil)
    }
    func saveRoll(_ roll: LocalRoll) async throws {}
    func deleteRoll(id: UUID) async throws {}
}

private struct FakeRecoveryParticipantRepository: ParticipantRepository {
    let participantsByRollID: [UUID: [LocalParticipant]]

    func fetchParticipants(forRollID rollID: UUID) async throws -> [LocalParticipant] {
        participantsByRollID[rollID] ?? []
    }

    func fetchParticipant(id: UUID) async throws -> LocalParticipant? {
        participantsByRollID.values.flatMap { $0 }.first(where: { $0.id == id })
    }

    func joinRoll(inviteToken: String) async throws -> JoinRollResult {
        JoinRollResult(rollID: UUID(), participantID: UUID())
    }

    func leaveRoll(rollID: UUID) async throws {}
    func saveParticipant(_ participant: LocalParticipant) async throws {}
    func deleteParticipant(id: UUID) async throws {}
}
