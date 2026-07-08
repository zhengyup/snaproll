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
    func developmentDiagnosticsReflectMirroredExposureState() async {
        let rollID = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!
        let cloudExposures = [
            makeExposure(
                id: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000101")!,
                rollID: rollID,
                exposureNumber: 1,
                renderSeed: "diag-seed"
            )
        ]
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: FakeDetailRollRepository(fetchRollResults: [.success(makeRoll(id: rollID, status: .shooting, exposures: 1))]),
            exposureRepository: FakeDetailExposureRepository(fetchByRollResults: [.success(cloudExposures)]),
            exposureMirrorStore: InMemoryExposureMirrorStore(),
            diagnosticsEnabled: true
        )

        await viewModel.load()

        #expect(viewModel.shouldShowDiagnostics)
        #expect(viewModel.diagnosticsRows.count == 1)
        #expect(viewModel.diagnosticsRows.first?.exposureNumber == 1)
        #expect(viewModel.diagnosticsRows.first?.syncState == .empty)
        #expect(viewModel.diagnosticsRows.first?.renderSeed == "diag-seed")
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
        #expect(viewModel.diagnosticsRows.isEmpty)
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
    func saveExposure(_ exposure: LocalExposure) async throws {}
    func saveExposures(_ exposures: [LocalExposure]) async throws {}
}

@MainActor
private final class InMemoryExposureMirrorStore: ExposureMirrorStore {
    private var exposuresByRollID: [UUID: [LocalExposure]] = [:]

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] ?? []
    }

    func mirrorCloudExposures(_ exposures: [LocalExposure], forRollID rollID: UUID) async throws -> [LocalExposure] {
        let merged = exposures.sorted { $0.exposure_number < $1.exposure_number }
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
    exposureNumber: Int,
    renderSeed: String
) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
        exposure_number: exposureNumber,
        render_seed: renderSeed,
        sync_state: .empty,
        updated_at: .now
    )
}
