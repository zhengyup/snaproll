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
    struct DiagnosticsSummary: Equatable {
        let activeIdentityLabel: String?
        let rollID: UUID
        let rollStatus: V2Domain.RollStatus
        let capturedCount: Int
        let remainingCount: Int
    }

    struct DiagnosticsRow: Identifiable, Equatable {
        let id: UUID
        let exposureNumber: Int
        let syncState: V2Domain.ExposureSyncState
        let renderSeed: String
        let localFileExists: Bool
        let localUploadFileExists: Bool
        let localOriginalPath: String?
        let uploadJPEGPath: String?
        let cloudStoragePath: String?
        let captureTimestamp: Date?
        let uploadedAt: Date?
    }

    @Published private(set) var state: V2PersonalRollDetailState = .idle
    @Published private(set) var roll: LocalRoll?
    @Published private(set) var mirroredExposures: [LocalExposure] = []
    @Published private(set) var isStartingRoll = false
    @Published private(set) var isUploadingPendingExposures = false
    @Published private(set) var lastUploadMessage: String?

    let rollID: UUID

    private let rollRepository: any RollRepository
    private let exposureRepository: any ExposureRepository
    private let exposureMirrorStore: any ExposureMirrorStore
    private let photoStorageService: PhotoStorageService
    private let uploadPipeline: (any ExposureUploadSyncing)?
    private let diagnosticsEnabled: Bool
    private let activeDevelopmentIdentityLabel: String?

    init(
        rollID: UUID,
        rollRepository: any RollRepository,
        exposureRepository: any ExposureRepository,
        exposureMirrorStore: any ExposureMirrorStore,
        photoStorageService: PhotoStorageService? = nil,
        uploadPipeline: (any ExposureUploadSyncing)? = nil,
        diagnosticsEnabled: Bool? = nil,
        activeDevelopmentIdentityLabel: String? = nil
    ) {
        self.rollID = rollID
        self.rollRepository = rollRepository
        self.exposureRepository = exposureRepository
        self.exposureMirrorStore = exposureMirrorStore
        self.photoStorageService = photoStorageService ?? PhotoStorageService()
        self.uploadPipeline = uploadPipeline
        self.diagnosticsEnabled = diagnosticsEnabled ?? AppConfig.V2.isExposureDiagnosticsEnabled
        self.activeDevelopmentIdentityLabel = activeDevelopmentIdentityLabel
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

    var shouldShowCaptureAction: Bool {
        roll?.status == .shooting && remainingExposures > 0
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
                renderSeed: exposure.render_seed,
                localFileExists: exposure.local_original_path.map { photoStorageService.fileExists(at: $0) } ?? false,
                localUploadFileExists: exposure.upload_jpeg_path.map { photoStorageService.fileExists(at: $0) } ?? false,
                localOriginalPath: exposure.local_original_path,
                uploadJPEGPath: exposure.upload_jpeg_path,
                cloudStoragePath: exposure.cloud_storage_path,
                captureTimestamp: exposure.captured_at,
                uploadedAt: exposure.uploaded_at
            )
        }
    }

    var shouldShowDiagnostics: Bool {
        diagnosticsEnabled
    }

    var uploadableExposureCount: Int {
        mirroredExposures.filter { $0.sync_state == .localOnly }.count
    }

    var shouldShowUploadAction: Bool {
        diagnosticsEnabled && uploadPipeline != nil && uploadableExposureCount > 0
    }

    var diagnosticsSummary: DiagnosticsSummary? {
        guard diagnosticsEnabled, let roll else {
            return nil
        }

        return DiagnosticsSummary(
            activeIdentityLabel: activeDevelopmentIdentityLabel,
            rollID: roll.id,
            rollStatus: roll.status,
            capturedCount: capturedExposures,
            remainingCount: remainingExposures
        )
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

    func uploadPendingExposures() async {
        guard let uploadPipeline, !isUploadingPendingExposures else {
            return
        }

        isUploadingPendingExposures = true
        lastUploadMessage = nil
        defer { isUploadingPendingExposures = false }

        do {
            let summary = try await uploadPipeline.uploadPendingExposures(forRollID: rollID)
            try await reloadLocalMirror()

            if summary.failedCount > 0 {
                lastUploadMessage = "\(summary.uploadedCount) uploaded, \(summary.failedCount) failed"
            } else {
                lastUploadMessage = "\(summary.uploadedCount) exposure(s) uploaded"
            }
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

    private func reloadLocalMirror() async throws {
        mirroredExposures = try await exposureMirrorStore.fetchExposures(forRollID: rollID)
            .sorted(by: { $0.exposure_number < $1.exposure_number })
    }
}
