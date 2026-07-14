import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2ExposureReconciliationCoordinatorTests {
    @Test
    func metadataPendingCloudFilledSamePathMarksLocalSynced() async throws {
        let fixture = ReconciliationFixture()
        let exposure = makeReconciliationExposure(
            rollID: fixture.roll.id,
            participantID: fixture.participant.id,
            syncState: .metadataPending
        )
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
        let cloud = makeCloudExposure(from: exposure, storagePath: exposure.canonicalCloudStoragePath)

        let store = ReconciliationMirrorStore(initialExposures: [fixture.roll.id: [exposure]])
        let coordinator = makeReconciler(fixture: fixture, store: store, cloudExposures: [cloud])

        await coordinator.reconcileRoll(id: fixture.roll.id)

        let reconciled = try #require(try await store.fetchExposures(forRollID: fixture.roll.id).first)
        #expect(reconciled.sync_state == .synced)
        #expect(reconciled.cloud_storage_path == exposure.canonicalCloudStoragePath)
        #expect(reconciled.last_error == nil)
        #expect(reconciled.last_reconciliation_rule == "CLOUD_FILLED_SAME_PATH")
    }

    @Test
    func failedWithStoragePathCloudFilledSamePathMarksLocalSynced() async throws {
        let fixture = ReconciliationFixture()
        let exposure = makeReconciliationExposure(
            rollID: fixture.roll.id,
            participantID: fixture.participant.id,
            syncState: .failed
        )
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
        exposure.last_error = "RPC timeout"
        let cloud = makeCloudExposure(from: exposure, storagePath: exposure.canonicalCloudStoragePath)
        let store = ReconciliationMirrorStore(initialExposures: [fixture.roll.id: [exposure]])
        let coordinator = makeReconciler(fixture: fixture, store: store, cloudExposures: [cloud])

        await coordinator.reconcileRoll(id: fixture.roll.id)

        let reconciled = try #require(try await store.fetchExposures(forRollID: fixture.roll.id).first)
        #expect(reconciled.sync_state == .synced)
        #expect(reconciled.last_error == nil)
    }

    @Test
    func localOnlyCloudEmptyRemainsUploadRetryable() async throws {
        let fixture = ReconciliationFixture()
        let exposure = makeReconciliationExposure(
            rollID: fixture.roll.id,
            participantID: fixture.participant.id,
            syncState: .localOnly
        )
        let cloud = makeCloudExposure(from: exposure, storagePath: nil)
        let store = ReconciliationMirrorStore(initialExposures: [fixture.roll.id: [exposure]])
        let coordinator = makeReconciler(fixture: fixture, store: store, cloudExposures: [cloud])

        await coordinator.reconcileRoll(id: fixture.roll.id)

        let reconciled = try #require(try await store.fetchExposures(forRollID: fixture.roll.id).first)
        #expect(reconciled.sync_state == .localOnly)
        #expect(reconciled.last_reconciliation_rule == "LOCAL_RETRY_CLOUD_EMPTY")
    }

    @Test
    func metadataPendingCloudEmptyRetriesMetadataOnly() async throws {
        let fixture = ReconciliationFixture()
        let exposure = makeReconciliationExposure(
            rollID: fixture.roll.id,
            participantID: fixture.participant.id,
            syncState: .metadataPending
        )
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
        let cloud = makeCloudExposure(from: exposure, storagePath: nil)
        let store = ReconciliationMirrorStore(initialExposures: [fixture.roll.id: [exposure]])
        let coordinator = makeReconciler(fixture: fixture, store: store, cloudExposures: [cloud])

        await coordinator.reconcileRoll(id: fixture.roll.id)

        let reconciled = try #require(try await store.fetchExposures(forRollID: fixture.roll.id).first)
        #expect(reconciled.sync_state == .metadataPending)
        #expect(reconciled.cloud_storage_path == exposure.canonicalCloudStoragePath)
    }

    @Test
    func syncedCloudFilledSamePathRemainsConsistent() async throws {
        let fixture = ReconciliationFixture()
        let exposure = makeReconciliationExposure(
            rollID: fixture.roll.id,
            participantID: fixture.participant.id,
            syncState: .synced
        )
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
        let cloud = makeCloudExposure(from: exposure, storagePath: exposure.canonicalCloudStoragePath)
        let store = ReconciliationMirrorStore(initialExposures: [fixture.roll.id: [exposure]])
        let coordinator = makeReconciler(fixture: fixture, store: store, cloudExposures: [cloud])

        await coordinator.reconcileRoll(id: fixture.roll.id)

        let reconciled = try #require(try await store.fetchExposures(forRollID: fixture.roll.id).first)
        #expect(reconciled.sync_state == .synced)
        #expect(reconciled.last_reconciliation_error == nil)
    }

    @Test
    func syncedCloudEmptyPreservesInconsistency() async throws {
        let fixture = ReconciliationFixture()
        let exposure = makeReconciliationExposure(
            rollID: fixture.roll.id,
            participantID: fixture.participant.id,
            syncState: .synced
        )
        let cloud = makeCloudExposure(from: exposure, storagePath: nil)
        let store = ReconciliationMirrorStore(initialExposures: [fixture.roll.id: [exposure]])
        let coordinator = makeReconciler(fixture: fixture, store: store, cloudExposures: [cloud])

        await coordinator.reconcileRoll(id: fixture.roll.id)

        let reconciled = try #require(try await store.fetchExposures(forRollID: fixture.roll.id).first)
        #expect(reconciled.sync_state == .failed)
        #expect(reconciled.last_reconciliation_rule == "LOCAL_SYNCED_CLOUD_EMPTY")
        #expect(reconciled.last_reconciliation_error != nil)
    }

    @Test
    func differentNonNullPathsCreateHardConsistencyError() async throws {
        let fixture = ReconciliationFixture()
        let exposure = makeReconciliationExposure(
            rollID: fixture.roll.id,
            participantID: fixture.participant.id,
            syncState: .metadataPending
        )
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
        let cloud = makeCloudExposure(from: exposure, storagePath: exposure.canonicalCloudStoragePath.replacingOccurrences(of: "001.jpg", with: "002.jpg"))
        let store = ReconciliationMirrorStore(initialExposures: [fixture.roll.id: [exposure]])
        let coordinator = makeReconciler(fixture: fixture, store: store, cloudExposures: [cloud])

        await coordinator.reconcileRoll(id: fixture.roll.id)

        let reconciled = try #require(try await store.fetchExposures(forRollID: fixture.roll.id).first)
        #expect(reconciled.sync_state == .failed)
        #expect(reconciled.last_reconciliation_rule == "PATH_MISMATCH")
    }

    @Test
    func cloudExposureMissingLocallyCreatesMirror() async throws {
        let fixture = ReconciliationFixture()
        let cloud = makeReconciliationExposure(
            rollID: fixture.roll.id,
            participantID: fixture.participant.id,
            syncState: .synced
        )
        cloud.cloud_storage_path = cloud.canonicalCloudStoragePath
        let store = ReconciliationMirrorStore(initialExposures: [:])
        let coordinator = makeReconciler(fixture: fixture, store: store, cloudExposures: [cloud])

        await coordinator.reconcileRoll(id: fixture.roll.id)

        let mirrored = try #require(try await store.fetchExposures(forRollID: fixture.roll.id).first)
        #expect(mirrored.id == cloud.id)
        #expect(mirrored.sync_state == .synced)
        #expect(mirrored.owner_user_id == fixture.userID)
        #expect(mirrored.last_reconciliation_rule == "CLOUD_EXPOSURE_CREATED_LOCAL_MIRROR")
    }

    @Test
    func missingLocalOriginalDoesNotCrashOrDeleteMetadata() async throws {
        let fixture = ReconciliationFixture()
        let exposure = makeReconciliationExposure(
            rollID: fixture.roll.id,
            participantID: fixture.participant.id,
            syncState: .localOnly
        )
        exposure.local_original_path = "/tmp/snaproll-missing-original.jpg"
        let cloud = makeCloudExposure(from: exposure, storagePath: nil)
        let store = ReconciliationMirrorStore(initialExposures: [fixture.roll.id: [exposure]])
        let coordinator = makeReconciler(fixture: fixture, store: store, cloudExposures: [cloud])

        await coordinator.reconcileRoll(id: fixture.roll.id)

        let reconciled = try #require(try await store.fetchExposures(forRollID: fixture.roll.id).first)
        #expect(reconciled.local_original_path == "/tmp/snaproll-missing-original.jpg")
        #expect(reconciled.sync_state == .failed)
        #expect(reconciled.last_reconciliation_error != nil)
    }

    @Test
    func syncRunnerSkipsExposureOwnedByDifferentIdentity() async throws {
        let rollID = UUID(uuidString: "14141414-0000-0000-0000-000000000010")!
        let currentUserID = UUID(uuidString: "14141414-0000-0000-0000-0000000000A1")!
        let otherUserID = UUID(uuidString: "14141414-0000-0000-0000-0000000000B1")!
        let currentExposure = makeReconciliationExposure(
            rollID: rollID,
            participantID: UUID(uuidString: "14141414-0000-0000-0000-000000000101")!,
            syncState: .localOnly
        )
        currentExposure.owner_user_id = currentUserID
        let otherExposure = makeReconciliationExposure(
            id: UUID(uuidString: "14141414-0000-0000-0000-000000000202")!,
            rollID: rollID,
            participantID: UUID(uuidString: "14141414-0000-0000-0000-000000000102")!,
            exposureNumber: 2,
            syncState: .localOnly
        )
        otherExposure.owner_user_id = otherUserID
        let store = ReconciliationMirrorStore(initialExposures: [rollID: [currentExposure, otherExposure]])
        let uploadStage = ReconciliationUploadStage(exposureMirrorStore: store)
        let metadataStage = ReconciliationMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            authRepository: ReconciliationAuthRepository(session: AuthSession(userID: currentUserID, displayName: "Current")),
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)

        #expect(summary.processedExposureIDs == [currentExposure.id])
        #expect(await uploadStage.processedExposureIDs == [currentExposure.id])
    }
}

private struct ReconciliationFixture {
    let userID = UUID(uuidString: "14141414-0000-0000-0000-0000000000A1")!
    let roll: LocalRoll
    let participant: LocalParticipant

    init() {
        let rollID = UUID(uuidString: "14141414-0000-0000-0000-000000000001")!
        self.roll = LocalRoll(
            id: rollID,
            title: "Reconciliation Roll",
            type: .personal,
            status: .shooting,
            film_stock_id: "kodakGold200",
            exposures_per_participant: 12,
            creator_id: userID,
            created_at: .now,
            started_at: .now
        )
        self.participant = LocalParticipant(
            id: UUID(uuidString: "14141414-0000-0000-0000-000000000101")!,
            roll_id: rollID,
            user_id: userID,
            display_name: "Current",
            status: .shooting,
            joined_at: .now
        )
    }
}

@MainActor
private final class ReconciliationMirrorStore: ExposureMirrorStore {
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

private struct ReconciliationAuthRepository: AuthRepository {
    let session: AuthSession?

    func currentSession() async throws -> AuthSession? { session }
    func currentUserID() async throws -> UUID? { session?.userID }
    func signOut() async throws {}
}

private struct ReconciliationRollRepository: RollRepository {
    let rolls: [LocalRoll]

    func fetchRoll(id: UUID) async throws -> LocalRoll? { rolls.first { $0.id == id } }
    func fetchRolls() async throws -> [LocalRoll] { rolls }
    func startRoll(id: UUID) async throws {}
    func revealRoll(id: UUID) async throws {}
    func createRoll(title: String, type: V2Domain.RollType, filmStockID: String, exposuresPerParticipant: Int, participantCap: Int) async throws -> CreateRollResult {
        CreateRollResult(rollID: UUID(), inviteToken: nil)
    }
    func saveRoll(_ roll: LocalRoll) async throws {}
    func deleteRoll(id: UUID) async throws {}
}

private struct ReconciliationParticipantRepository: ParticipantRepository {
    let participants: [LocalParticipant]

    func fetchParticipants(forRollID rollID: UUID) async throws -> [LocalParticipant] {
        participants.filter { $0.roll_id == rollID }
    }
    func fetchParticipant(id: UUID) async throws -> LocalParticipant? { participants.first { $0.id == id } }
    func joinRoll(inviteToken: String) async throws -> JoinRollResult { JoinRollResult(rollID: UUID(), participantID: UUID()) }
    func leaveRoll(rollID: UUID) async throws {}
    func saveParticipant(_ participant: LocalParticipant) async throws {}
    func deleteParticipant(id: UUID) async throws {}
}

private struct ReconciliationExposureRepository: ExposureRepository {
    let exposures: [LocalExposure]

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposures.filter { $0.roll_id == rollID }
    }
    func fetchExposures(forParticipantID participantID: UUID) async throws -> [LocalExposure] {
        exposures.filter { $0.participant_id == participantID }
    }
    func fetchExposure(id: UUID) async throws -> LocalExposure? { exposures.first { $0.id == id } }
    func completeExposure(id: UUID, storagePath: String) async throws -> CompleteExposureResult {
        CompleteExposureResult(participantFinished: false, rollReadyToReveal: false)
    }
    func saveExposure(_ exposure: LocalExposure) async throws {}
    func saveExposures(_ exposures: [LocalExposure]) async throws {}
}

private actor ReconciliationUploadStage: ExposureUploadStageSyncing {
    private(set) var processedExposureIDs: [UUID] = []
    private let exposureMirrorStore: any ExposureMirrorStore

    init(exposureMirrorStore: any ExposureMirrorStore) {
        self.exposureMirrorStore = exposureMirrorStore
    }

    func processUploadStage(for exposure: LocalExposure, rollID: UUID) async throws {
        let id = await MainActor.run { exposure.id }
        processedExposureIDs.append(id)
        await MainActor.run {
            exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
            exposure.sync_state = .metadataPending
        }
        try await exposureMirrorStore.saveExposure(exposure)
    }
}

private actor ReconciliationMetadataStage: ExposureMetadataStageSyncing {
    private let exposureMirrorStore: any ExposureMirrorStore

    init(exposureMirrorStore: any ExposureMirrorStore) {
        self.exposureMirrorStore = exposureMirrorStore
    }

    func processMetadataStage(for exposure: LocalExposure) async throws {
        await MainActor.run {
            exposure.sync_state = .synced
        }
        try await exposureMirrorStore.saveExposure(exposure)
    }
}

@MainActor
private func makeReconciler(
    fixture: ReconciliationFixture,
    store: ReconciliationMirrorStore,
    cloudExposures: [LocalExposure]
) -> V2ExposureReconciliationCoordinator {
    V2ExposureReconciliationCoordinator(
        authRepository: ReconciliationAuthRepository(session: AuthSession(userID: fixture.userID, displayName: "Current")),
        rollRepository: ReconciliationRollRepository(rolls: [fixture.roll]),
        participantRepository: ReconciliationParticipantRepository(participants: [fixture.participant]),
        exposureRepository: ReconciliationExposureRepository(exposures: cloudExposures),
        exposureMirrorStore: store,
        photoStorageService: PhotoStorageService(
            storageRootDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    )
}

private func makeReconciliationExposure(
    id: UUID = UUID(uuidString: "14141414-0000-0000-0000-000000000201")!,
    rollID: UUID,
    participantID: UUID,
    exposureNumber: Int = 1,
    syncState: V2Domain.ExposureSyncState
) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: participantID,
        exposure_number: exposureNumber,
        render_seed: "reconcile-\(exposureNumber)",
        sync_state: syncState,
        updated_at: .now
    )
}

private func makeCloudExposure(from exposure: LocalExposure, storagePath: String?) -> LocalExposure {
    LocalExposure(
        id: exposure.id,
        roll_id: exposure.roll_id,
        participant_id: exposure.participant_id,
        exposure_number: exposure.exposure_number,
        render_seed: exposure.render_seed,
        cloud_storage_path: storagePath,
        sync_state: storagePath == nil ? .empty : .synced,
        uploaded_at: storagePath == nil ? nil : .now,
        updated_at: .now
    )
}
