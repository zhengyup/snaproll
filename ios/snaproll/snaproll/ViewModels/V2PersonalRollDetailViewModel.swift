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
        let pendingCount: Int
        let failedCount: Int
        let isSynchronizing: Bool
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
        let lastError: String?
    }

    @Published private(set) var state: V2PersonalRollDetailState = .idle
    @Published private(set) var roll: LocalRoll?
    @Published private(set) var mirroredExposures: [LocalExposure] = []
    @Published private(set) var isStartingRoll = false
    @Published private(set) var isSynchronizing = false
    @Published private(set) var lastSyncMessage: String?

    let rollID: UUID

    private let rollRepository: any RollRepository
    private let exposureRepository: any ExposureRepository
    private let exposureMirrorStore: any ExposureMirrorStore
    private let photoStorageService: PhotoStorageService
    private let syncRunner: (any ExposureSyncRunning)?
    private let diagnosticsEnabled: Bool
    private let activeDevelopmentIdentityLabel: String?

    init(
        rollID: UUID,
        rollRepository: any RollRepository,
        exposureRepository: any ExposureRepository,
        exposureMirrorStore: any ExposureMirrorStore,
        photoStorageService: PhotoStorageService? = nil,
        syncRunner: (any ExposureSyncRunning)? = nil,
        diagnosticsEnabled: Bool? = nil,
        activeDevelopmentIdentityLabel: String? = nil
    ) {
        self.rollID = rollID
        self.rollRepository = rollRepository
        self.exposureRepository = exposureRepository
        self.exposureMirrorStore = exposureMirrorStore
        self.photoStorageService = photoStorageService ?? PhotoStorageService()
        self.syncRunner = syncRunner
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
                uploadedAt: exposure.uploaded_at,
                lastError: exposure.last_error
            )
        }
    }

    var shouldShowDiagnostics: Bool {
        diagnosticsEnabled
    }

    var pendingSyncExposureCount: Int {
        mirroredExposures.filter { exposure in
            switch exposure.sync_state {
            case .localOnly, .uploading, .metadataPending:
                return true
            case .failed:
                return true
            case .empty, .synced:
                return false
            }
        }.count
    }

    var failedSyncExposureCount: Int {
        mirroredExposures.filter { $0.sync_state == .failed }.count
    }

    var shouldShowProcessPendingAction: Bool {
        diagnosticsEnabled && syncRunner != nil && pendingSyncExposureCount > 0
    }

    var shouldShowRetryFailedAction: Bool {
        diagnosticsEnabled && syncRunner != nil && failedSyncExposureCount > 0
    }

    var shouldShowForceRefreshAction: Bool {
        diagnosticsEnabled
    }

    var userFacingSyncStatus: String? {
        if isSynchronizing {
            return "Syncing…"
        }

        if roll?.status == .readyToReveal {
            return "Ready to Reveal"
        }

        if failedSyncExposureCount > 0 {
            return diagnosticsEnabled ? "Sync failed" : "Waiting for upload…"
        }

        if mirroredExposures.contains(where: { $0.sync_state == .metadataPending }) {
            return "Syncing…"
        }

        if mirroredExposures.contains(where: { $0.sync_state == .uploading }) {
            return "Uploading…"
        }

        if mirroredExposures.contains(where: { $0.sync_state == .localOnly }) {
            return "Waiting for upload…"
        }

        return nil
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
            remainingCount: remainingExposures,
            pendingCount: pendingSyncExposureCount,
            failedCount: failedSyncExposureCount,
            isSynchronizing: isSynchronizing
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

    func handleAppear() async {
        await load()
        await synchronizeIfNeeded()
    }

    func handleCaptureSessionEnded() async {
        await load()
        await synchronizeIfNeeded()
    }

    func handleSceneBecameActive() async {
        await synchronizeIfNeeded()
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

    func processPendingExposures() async {
        await runSynchronization()
    }

    func retryFailedSynchronization() async {
        await runSynchronization()
    }

    func forceRefresh() async {
        await load()
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

    private func synchronizeIfNeeded() async {
        guard pendingSyncExposureCount > 0 else {
            return
        }

        await runSynchronization()
    }

    private func runSynchronization() async {
        guard let syncRunner, !isSynchronizing else {
            return
        }

        isSynchronizing = true
        lastSyncMessage = nil
        defer { isSynchronizing = false }

        do {
            let summary = try await syncRunner.processPendingExposures(forRollID: rollID)
            try await reloadFromSources()

            if summary.processedCount == 0 {
                lastSyncMessage = "No pending work"
            } else if summary.failedCount > 0 {
                lastSyncMessage = "\(summary.syncedCount) synced, \(summary.failedCount) failed"
            } else {
                lastSyncMessage = "\(summary.syncedCount) exposure(s) synced"
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
