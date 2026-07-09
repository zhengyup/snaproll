import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2PersonalRollDetailViewModelTests {
    @Test
    func startRollInvokesRepositoryAndFetchesExposureSlots() async {
        let rollID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
        let startedRoll = makeRoll(id: rollID, status: .shooting)
        let cloudExposures = [
            makeExposure(
                id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000101")!,
                rollID: rollID,
                exposureNumber: 1,
                renderSeed: "seed-1"
            ),
            makeExposure(
                id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000102")!,
                rollID: rollID,
                exposureNumber: 2,
                renderSeed: "seed-2"
            )
        ]
        let rollRepository = FakeDetailRollRepository(
            fetchRollResults: [.success(makeRoll(id: rollID, status: .draft)), .success(startedRoll)]
        )
        let exposureRepository = FakeDetailExposureRepository(fetchByRollResults: [.success(cloudExposures)])
        let mirrorStore = InMemoryExposureMirrorStore()
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: rollRepository,
            exposureRepository: exposureRepository,
            exposureMirrorStore: mirrorStore,
            diagnosticsEnabled: true
        )

        await viewModel.load()
        await viewModel.startRoll()

        let startedIDs = await rollRepository.startedRollIDs
        let fetchedRollIDs = await exposureRepository.fetchedRollIDs
        let mirrored = try? await mirrorStore.fetchExposures(forRollID: rollID)

        #expect(startedIDs == [rollID])
        #expect(fetchedRollIDs == [rollID])
        #expect(viewModel.roll?.status == .shooting)
        #expect(mirrored?.count == 2)
        #expect(viewModel.mirroredExposures.count == 2)
    }

    @Test
    func reopeningRollDoesNotDuplicateMirroredExposureRecords() async throws {
        let rollID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!
        let shootingRoll = makeRoll(id: rollID, status: .shooting)
        let cloudExposures = [
            makeExposure(
                id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000101")!,
                rollID: rollID,
                exposureNumber: 1,
                renderSeed: "seed-a"
            ),
            makeExposure(
                id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000102")!,
                rollID: rollID,
                exposureNumber: 2,
                renderSeed: "seed-b"
            )
        ]
        let rollRepository = FakeDetailRollRepository(
            fetchRollResults: [.success(shootingRoll), .success(shootingRoll)]
        )
        let exposureRepository = FakeDetailExposureRepository(
            fetchByRollResults: [.success(cloudExposures), .success(cloudExposures)]
        )
        let mirrorStore = InMemoryExposureMirrorStore()
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: rollRepository,
            exposureRepository: exposureRepository,
            exposureMirrorStore: mirrorStore,
            diagnosticsEnabled: true
        )

        await viewModel.load()
        await viewModel.load()

        let mirrored = try await mirrorStore.fetchExposures(forRollID: rollID)
        #expect(mirrored.count == 2)
        #expect(Set(mirrored.map(\.id)).count == 2)
    }

    @Test
    func progressShowsZeroCapturedInitially() async {
        let rollID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!
        let cloudExposures = (1...3).map { index in
            makeExposure(
                id: UUID(uuidString: String(format: "CCCCCCCC-0000-0000-0000-00000000010%d", index))!,
                rollID: rollID,
                exposureNumber: index,
                renderSeed: "seed-\(index)"
            )
        }
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: FakeDetailRollRepository(fetchRollResults: [.success(makeRoll(id: rollID, status: .shooting, exposures: 3))]),
            exposureRepository: FakeDetailExposureRepository(fetchByRollResults: [.success(cloudExposures)]),
            exposureMirrorStore: InMemoryExposureMirrorStore(),
            diagnosticsEnabled: true
        )

        await viewModel.load()

        #expect(viewModel.totalExposures == 3)
        #expect(viewModel.capturedExposures == 0)
        #expect(viewModel.remainingExposures == 3)
    }

    @Test
    func developmentDiagnosticsReflectMirroredExposureState() async throws {
        let rollID = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!
        let pendingExposure = makeExposure(
            id: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            renderSeed: "diag-seed",
            syncState: .localOnly
        )
        pendingExposure.local_original_path = "/tmp/test.jpg"

        let mirrorStore = InMemoryExposureMirrorStore()
        try await mirrorStore.saveExposure(pendingExposure)
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: FakeDetailRollRepository(fetchRollResults: [.success(makeRoll(id: rollID, status: .shooting, exposures: 1))]),
            exposureRepository: FakeDetailExposureRepository(fetchByRollResults: [.success([makeExposure(id: pendingExposure.id, rollID: rollID, exposureNumber: 1, renderSeed: "diag-seed")])]),
            exposureMirrorStore: mirrorStore,
            diagnosticsEnabled: true,
            activeDevelopmentIdentityLabel: "Creator"
        )

        await viewModel.load()

        #expect(viewModel.shouldShowDiagnostics)
        #expect(viewModel.diagnosticsSummary?.activeIdentityLabel == "Creator")
        #expect(viewModel.diagnosticsSummary?.rollID == rollID)
        #expect(viewModel.diagnosticsSummary?.rollStatus == .shooting)
        #expect(viewModel.diagnosticsSummary?.capturedCount == 1)
        #expect(viewModel.diagnosticsSummary?.remainingCount == 0)
        #expect(viewModel.diagnosticsSummary?.pendingCount == 1)
        #expect(viewModel.diagnosticsRows.count == 1)
        #expect(viewModel.diagnosticsRows.first?.exposureNumber == 1)
        #expect(viewModel.diagnosticsRows.first?.syncState == .localOnly)
        #expect(viewModel.diagnosticsRows.first?.renderSeed == "diag-seed")
        #expect(viewModel.shouldShowProcessPendingAction == false)
    }

    @Test
    func diagnosticsAreHiddenWhenDisabled() async {
        let rollID = UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: FakeDetailRollRepository(fetchRollResults: [.success(makeRoll(id: rollID, status: .shooting, exposures: 1))]),
            exposureRepository: FakeDetailExposureRepository(
                fetchByRollResults: [.success([makeExposure(id: UUID(), rollID: rollID, exposureNumber: 1, renderSeed: "seed")])]
            ),
            exposureMirrorStore: InMemoryExposureMirrorStore(),
            diagnosticsEnabled: false
        )

        await viewModel.load()

        #expect(viewModel.shouldShowDiagnostics == false)
        #expect(viewModel.diagnosticsSummary == nil)
        #expect(viewModel.diagnosticsRows.isEmpty)
    }

    @Test
    func handleAppearStartsSynchronizationWhenPendingExposureExists() async throws {
        let rollID = UUID(uuidString: "F1F1F1F1-0000-0000-0000-000000000001")!
        let exposureID = UUID(uuidString: "F1F1F1F1-0000-0000-0000-000000000101")!
        let pendingExposure = makeExposure(
            id: exposureID,
            rollID: rollID,
            exposureNumber: 1,
            renderSeed: "sync-seed",
            syncState: .localOnly
        )
        pendingExposure.local_original_path = "/tmp/pending.jpg"

        let mirrorStore = InMemoryExposureMirrorStore()
        try await mirrorStore.saveExposure(pendingExposure)
        let syncRunner = RecordingExposureSyncRunner()
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: FakeDetailRollRepository(fetchRollResults: [
                .success(makeRoll(id: rollID, status: .shooting, exposures: 1)),
                .success(makeRoll(id: rollID, status: .shooting, exposures: 1))
            ]),
            exposureRepository: FakeDetailExposureRepository(
                fetchByRollResults: [
                    .success([makeExposure(id: exposureID, rollID: rollID, exposureNumber: 1, renderSeed: "sync-seed")]),
                    .success([makeExposure(id: exposureID, rollID: rollID, exposureNumber: 1, renderSeed: "sync-seed")])
                ]
            ),
            exposureMirrorStore: mirrorStore,
            syncRunner: syncRunner,
            diagnosticsEnabled: true
        )

        await viewModel.handleAppear()

        #expect(syncRunner.processedRollIDs == [rollID])
        #expect(viewModel.lastSyncMessage == "1 exposure(s) synced")
    }

    @Test
    func handleCaptureSessionEndedStartsSynchronizationWhenPendingExposureExists() async throws {
        let rollID = UUID(uuidString: "F2F2F2F2-0000-0000-0000-000000000001")!
        let exposureID = UUID(uuidString: "F2F2F2F2-0000-0000-0000-000000000101")!
        let pendingExposure = makeExposure(
            id: exposureID,
            rollID: rollID,
            exposureNumber: 1,
            renderSeed: "capture-seed",
            syncState: .localOnly
        )
        pendingExposure.local_original_path = "/tmp/pending.jpg"

        let mirrorStore = InMemoryExposureMirrorStore()
        try await mirrorStore.saveExposure(pendingExposure)
        let syncRunner = RecordingExposureSyncRunner()
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: FakeDetailRollRepository(fetchRollResults: [
                .success(makeRoll(id: rollID, status: .shooting, exposures: 1)),
                .success(makeRoll(id: rollID, status: .shooting, exposures: 1))
            ]),
            exposureRepository: FakeDetailExposureRepository(
                fetchByRollResults: [
                    .success([makeExposure(id: exposureID, rollID: rollID, exposureNumber: 1, renderSeed: "capture-seed")]),
                    .success([makeExposure(id: exposureID, rollID: rollID, exposureNumber: 1, renderSeed: "capture-seed")])
                ]
            ),
            exposureMirrorStore: mirrorStore,
            syncRunner: syncRunner,
            diagnosticsEnabled: true
        )

        await viewModel.handleCaptureSessionEnded()

        #expect(syncRunner.processedRollIDs == [rollID])
        #expect(viewModel.lastSyncMessage == "1 exposure(s) synced")
    }

    @Test
    func retryAndProcessActionsUseSameSyncRunner() async throws {
        let rollID = UUID(uuidString: "F3F3F3F3-0000-0000-0000-000000000001")!
        let failedExposure = makeExposure(
            id: UUID(uuidString: "F3F3F3F3-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            renderSeed: "failed-seed",
            syncState: .failed
        )
        failedExposure.local_original_path = "/tmp/failed.jpg"

        let mirrorStore = InMemoryExposureMirrorStore()
        try await mirrorStore.saveExposure(failedExposure)
        let syncRunner = RecordingExposureSyncRunner()
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: FakeDetailRollRepository(fetchRollResults: [
                .success(makeRoll(id: rollID, status: .shooting, exposures: 1)),
                .success(makeRoll(id: rollID, status: .shooting, exposures: 1))
            ]),
            exposureRepository: FakeDetailExposureRepository(fetchByRollResults: [
                .success([makeExposure(id: failedExposure.id, rollID: rollID, exposureNumber: 1, renderSeed: "failed-seed")]),
                .success([makeExposure(id: failedExposure.id, rollID: rollID, exposureNumber: 1, renderSeed: "failed-seed")])
            ]),
            exposureMirrorStore: mirrorStore,
            syncRunner: syncRunner,
            diagnosticsEnabled: true
        )

        await viewModel.processPendingExposures()
        await viewModel.retryFailedSynchronization()

        #expect(syncRunner.processedRollIDs == [rollID, rollID])
    }
}

private actor FakeDetailRollRepository: RollRepository {
    private var fetchRollResults: [Result<LocalRoll?, Error>]
    private(set) var startedRollIDs: [UUID] = []

    init(fetchRollResults: [Result<LocalRoll?, Error>]) {
        self.fetchRollResults = fetchRollResults
    }

    func fetchRoll(id: UUID) async throws -> LocalRoll? {
        guard !fetchRollResults.isEmpty else {
            return nil
        }

        let result = fetchRollResults.removeFirst()
        return try result.get()
    }

    func fetchRolls() async throws -> [LocalRoll] { [] }
    func fetchAllRolls() async throws -> [LocalRoll] { [] }

    func startRoll(id: UUID) async throws {
        startedRollIDs.append(id)
    }

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

private actor FakeDetailExposureRepository: ExposureRepository {
    private var fetchByRollResults: [Result<[LocalExposure], Error>]
    private(set) var fetchedRollIDs: [UUID] = []

    init(fetchByRollResults: [Result<[LocalExposure], Error>]) {
        self.fetchByRollResults = fetchByRollResults
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        fetchedRollIDs.append(rollID)
        guard !fetchByRollResults.isEmpty else {
            return []
        }

        let result = fetchByRollResults.removeFirst()
        return try result.get()
    }

    func fetchExposures(forParticipantID participantID: UUID) async throws -> [LocalExposure] { [] }
    func fetchExposure(id: UUID) async throws -> LocalExposure? { nil }
    func completeExposure(id: UUID, storagePath: String) async throws -> CompleteExposureResult {
        CompleteExposureResult(participantFinished: false, rollReadyToReveal: false)
    }
    func saveExposure(_ exposure: LocalExposure) async throws {}
    func saveExposures(_ exposures: [LocalExposure]) async throws {}
}

@MainActor
private final class RecordingExposureSyncRunner: ExposureSyncRunning {
    private(set) var processedRollIDs: [UUID] = []
    private let result: V2ExposureSyncRunSummary

    init(
        result: V2ExposureSyncRunSummary = V2ExposureSyncRunSummary(
            processedExposureIDs: [UUID()],
            syncedExposureIDs: [UUID()],
            failedExposureIDs: []
        )
    ) {
        self.result = result
    }

    func processPendingExposures(forRollID rollID: UUID) async throws -> V2ExposureSyncRunSummary {
        processedRollIDs.append(rollID)
        return result
    }
}

@MainActor
private final class InMemoryExposureMirrorStore: ExposureMirrorStore {
    private var exposuresByRollID: [UUID: [LocalExposure]] = [:]

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] ?? []
    }

    func mirrorCloudExposures(_ exposures: [LocalExposure], forRollID rollID: UUID) async throws -> [LocalExposure] {
        let existingByID = Dictionary(uniqueKeysWithValues: (exposuresByRollID[rollID] ?? []).map { ($0.id, $0) })
        let merged = exposures.map { exposure in
            guard let existing = existingByID[exposure.id] else {
                return exposure
            }

            let cloudHasUploadedAsset = exposure.cloud_storage_path != nil
            return LocalExposure(
                id: exposure.id,
                roll_id: exposure.roll_id,
                participant_id: exposure.participant_id,
                exposure_number: exposure.exposure_number,
                render_seed: exposure.render_seed,
                local_original_path: existing.local_original_path,
                upload_jpeg_path: existing.upload_jpeg_path,
                cloud_storage_path: exposure.cloud_storage_path ?? existing.cloud_storage_path,
                rendered_cache_path: existing.rendered_cache_path,
                sync_state: cloudHasUploadedAsset ? .synced : existing.sync_state,
                captured_at: existing.captured_at ?? exposure.captured_at,
                uploaded_at: exposure.uploaded_at ?? existing.uploaded_at,
                last_error: cloudHasUploadedAsset ? nil : existing.last_error,
                updated_at: max(existing.updated_at, exposure.updated_at)
            )
        }.sorted { $0.exposure_number < $1.exposure_number }
        exposuresByRollID[rollID] = merged
        return merged
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

private func makeRoll(
    id: UUID,
    status: V2Domain.RollStatus,
    exposures: Int = 12
) -> LocalRoll {
    LocalRoll(
        id: id,
        title: "Test Roll",
        type: .personal,
        status: status,
        film_stock_id: FilmStock.kodakGold200.rawValue,
        exposures_per_participant: exposures,
        creator_id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
        created_at: .now
    )
}

private func makeExposure(
    id: UUID,
    rollID: UUID,
    participantID: UUID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
    exposureNumber: Int,
    renderSeed: String,
    storagePath: String? = nil,
    syncState: V2Domain.ExposureSyncState = .empty
) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: participantID,
        exposure_number: exposureNumber,
        render_seed: renderSeed,
        cloud_storage_path: storagePath,
        sync_state: syncState,
        updated_at: .now
    )
}
