import Combine
import Foundation

enum V2PersonalRollDetailState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class V2PersonalRollDetailViewModel: ObservableObject {
    struct DiagnosticsRow: Identifiable, Equatable {
        let id: UUID
        let exposureNumber: Int
        let syncState: V2Domain.ExposureSyncState
        let renderSeed: String
    }

    @Published private(set) var state: V2PersonalRollDetailState = .idle
    @Published private(set) var roll: LocalRoll?
    @Published private(set) var mirroredExposures: [LocalExposure] = []
    @Published private(set) var isStartingRoll = false

    let rollID: UUID

    private let rollRepository: any RollRepository
    private let exposureRepository: any ExposureRepository
    private let exposureMirrorStore: any ExposureMirrorStore
    private let diagnosticsEnabled: Bool

    init(
        rollID: UUID,
        rollRepository: any RollRepository,
        exposureRepository: any ExposureRepository,
        exposureMirrorStore: any ExposureMirrorStore,
        diagnosticsEnabled: Bool? = nil
    ) {
        self.rollID = rollID
        self.rollRepository = rollRepository
        self.exposureRepository = exposureRepository
        self.exposureMirrorStore = exposureMirrorStore
        self.diagnosticsEnabled = diagnosticsEnabled ?? AppConfig.V2.isExposureDiagnosticsEnabled
    }

    var filmLabel: String {
        guard let roll else {
            return "Unknown Film"
        }

        return FilmStock(rawValue: roll.film_stock_id)?.displayName ?? roll.film_stock_id
    }

    var statusLabel: String {
        roll?.status.rawValue.replacingOccurrences(of: "_", with: " ") ?? "Loading"
    }

    var totalExposures: Int {
        if !mirroredExposures.isEmpty {
            return mirroredExposures.count
        }

        return roll?.exposures_per_participant ?? 0
    }

    var capturedExposures: Int {
        mirroredExposures.filter { exposure in
            exposure.sync_state != .empty
                || exposure.local_original_path != nil
                || exposure.cloud_storage_path != nil
                || exposure.captured_at != nil
        }.count
    }

    var remainingExposures: Int {
        max(totalExposures - capturedExposures, 0)
    }

    var shouldShowStartRoll: Bool {
        roll?.status == .draft
    }

    var diagnosticsRows: [DiagnosticsRow] {
        guard diagnosticsEnabled else {
            return []
        }

        return mirroredExposures.map { exposure in
            DiagnosticsRow(
                id: exposure.id,
                exposureNumber: exposure.exposure_number,
                syncState: exposure.sync_state,
                renderSeed: exposure.render_seed
            )
        }
    }

    var shouldShowDiagnostics: Bool {
        diagnosticsEnabled
    }

    func load() async {
        state = .loading

        do {
            try await reloadFromSources()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func startRoll() async {
        guard !isStartingRoll else {
            return
        }

        isStartingRoll = true
        defer { isStartingRoll = false }

        do {
            try await rollRepository.startRoll(id: rollID)
            try await reloadFromSources()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func reloadFromSources() async throws {
        guard let fetchedRoll = try await rollRepository.fetchRoll(id: rollID) else {
            throw V2RepositoryError.notFound("The selected roll could not be found.")
        }

        let mirrored: [LocalExposure]
        if fetchedRoll.status == .shooting || fetchedRoll.status == .readyToReveal || fetchedRoll.status == .revealed {
            let cloudExposures = try await exposureRepository.fetchExposures(forRollID: rollID)
            mirrored = try await exposureMirrorStore.mirrorCloudExposures(cloudExposures, forRollID: rollID)
        } else {
            mirrored = []
        }

        roll = fetchedRoll
        mirroredExposures = mirrored.sorted(by: { $0.exposure_number < $1.exposure_number })
    }
}
