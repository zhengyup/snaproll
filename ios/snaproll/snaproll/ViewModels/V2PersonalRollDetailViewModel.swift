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
        let isSharedRoll: Bool
        let currentParticipantID: UUID?
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
        let recoveryFromState: String?
        let recoveryToState: String?
        let recoveryReason: String?
        let recoveryError: String?
        let lastRecoveredAt: Date?
    }

    struct ParticipantProgressRow: Identifiable, Equatable {
        let id: UUID
        let userID: UUID
        let displayName: String
        let status: V2Domain.ParticipantStatus
        let isCurrentUser: Bool
        let isCreator: Bool
    }

    @Published private(set) var state: V2PersonalRollDetailState = .idle
    @Published private(set) var roll: LocalRoll?
    @Published private(set) var currentSession: AuthSession?
    @Published private(set) var participants: [LocalParticipant] = []
    @Published private(set) var mirroredExposures: [LocalExposure] = []
    @Published private(set) var isStartingRoll = false
    @Published private(set) var isRevealingRoll = false
    @Published private(set) var isSynchronizing = false
    @Published private(set) var lastSyncMessage: String?

    let rollID: UUID

    private let rollRepository: any RollRepository
    private let authRepository: (any AuthRepository)?
    private let participantRepository: (any ParticipantRepository)?
    private let exposureRepository: any ExposureRepository
    private let exposureMirrorStore: any ExposureMirrorStore
    private let photoStorageService: PhotoStorageService
    private let syncRunner: (any ExposureSyncRunning)?
    private let pendingRecoveryCoordinator: (any PendingExposureRecovering)?
    private let diagnosticsEnabled: Bool
    private let activeDevelopmentIdentityLabel: String?

    init(
        rollID: UUID,
        rollRepository: any RollRepository,
        authRepository: (any AuthRepository)? = nil,
        participantRepository: (any ParticipantRepository)? = nil,
        exposureRepository: any ExposureRepository,
        exposureMirrorStore: any ExposureMirrorStore,
        photoStorageService: PhotoStorageService? = nil,
        syncRunner: (any ExposureSyncRunning)? = nil,
        pendingRecoveryCoordinator: (any PendingExposureRecovering)? = nil,
        diagnosticsEnabled: Bool? = nil,
        activeDevelopmentIdentityLabel: String? = nil
    ) {
        self.rollID = rollID
        self.rollRepository = rollRepository
        self.authRepository = authRepository
        self.participantRepository = participantRepository
        self.exposureRepository = exposureRepository
        self.exposureMirrorStore = exposureMirrorStore
        self.photoStorageService = photoStorageService ?? PhotoStorageService()
        self.syncRunner = syncRunner
        self.pendingRecoveryCoordinator = pendingRecoveryCoordinator
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

    var isSharedRoll: Bool {
        roll?.type == .shared
    }

    var currentParticipant: LocalParticipant? {
        guard let currentUserID = currentSession?.userID else {
            return nil
        }

        return participants.first(where: { $0.user_id == currentUserID })
    }

    var isCreator: Bool {
        guard let roll, let currentUserID = currentSession?.userID else {
            return false
        }

        return roll.creator_id == currentUserID
    }

    var currentParticipantDisplayName: String? {
        currentParticipant?.display_name ?? currentSession?.displayName
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

    var shouldShowRevealAction: Bool {
        guard roll?.status == .readyToReveal else {
            return false
        }

        if isSharedRoll {
            return isCreator
        }

        return true
    }

    var shouldShowViewGalleryAction: Bool {
        roll?.status == .revealed
    }

    var sharedReadyMessage: String? {
        guard isSharedRoll else {
            return nil
        }

        if roll?.status == .readyToReveal, !isCreator {
            return "Waiting for the creator to reveal the finished roll."
        }

        if roll?.status == .shooting, let currentParticipant, currentParticipant.status == .finished {
            return "Your exposures are complete. Waiting for the remaining participants."
        }

        return nil
    }

    var shouldShowParticipantProgress: Bool {
        isSharedRoll && !participants.isEmpty
    }

    var participantProgressRows: [ParticipantProgressRow] {
        guard let currentUserID = currentSession?.userID, let roll else {
            return participants.map { participant in
                ParticipantProgressRow(
                    id: participant.id,
                    userID: participant.user_id,
                    displayName: participant.display_name ?? "Participant",
                    status: participant.status,
                    isCurrentUser: false,
                    isCreator: false
                )
            }
        }

        return participants.map { participant in
            ParticipantProgressRow(
                id: participant.id,
                userID: participant.user_id,
                displayName: participant.display_name ?? "Participant",
                status: participant.status,
                isCurrentUser: participant.user_id == currentUserID,
                isCreator: participant.user_id == roll.creator_id
            )
        }
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
                lastError: exposure.last_error,
                recoveryFromState: exposure.last_recovery_from_state,
                recoveryToState: exposure.last_recovery_to_state,
                recoveryReason: exposure.last_recovery_reason,
                recoveryError: exposure.last_recovery_error,
                lastRecoveredAt: exposure.last_recovered_at
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
            isSharedRoll: roll.type == .shared,
            currentParticipantID: currentParticipant?.id,
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
        await recoverPendingWorkIfNeeded()
    }

    func handleCaptureSessionEnded() async {
        await load()
        await synchronizeIfNeeded()
    }

    func handleSceneBecameActive() async {
        await recoverPendingWorkIfNeeded()
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

    @discardableResult
    func revealRoll() async -> Bool {
        guard shouldShowRevealAction, !isRevealingRoll else {
            return false
        }

        isRevealingRoll = true
        defer { isRevealingRoll = false }

        do {
            try await rollRepository.revealRoll(id: rollID)
            try await reloadFromSources()
            state = .loaded
            return roll?.status == .revealed
        } catch {
            state = .failed(error.localizedDescription)
            return false
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

    func refreshForSharedStateSynchronization() async throws -> V2Domain.RollStatus? {
        try await reloadFromSources()
        state = .loaded
        return roll?.status
    }

    private func reloadFromSources() async throws {
        guard let fetchedRoll = try await rollRepository.fetchRoll(id: rollID) else {
            throw V2RepositoryError.notFound("The selected roll could not be found.")
        }

        let fetchedSession = try await authRepository?.currentSession()
        let fetchedParticipants: [LocalParticipant]
        if fetchedRoll.type == .shared, let participantRepository {
            fetchedParticipants = try await participantRepository.fetchParticipants(forRollID: rollID)
        } else {
            fetchedParticipants = []
        }

        let mirrored: [LocalExposure]
        if fetchedRoll.status == .shooting || fetchedRoll.status == .readyToReveal || fetchedRoll.status == .revealed {
            let cloudExposures: [LocalExposure]
            if fetchedRoll.type == .shared,
               let currentUserID = fetchedSession?.userID,
               let currentParticipant = fetchedParticipants.first(where: { $0.user_id == currentUserID }) {
                cloudExposures = try await exposureRepository.fetchExposures(forParticipantID: currentParticipant.id)
            } else {
                cloudExposures = try await exposureRepository.fetchExposures(forRollID: rollID)
            }
            mirrored = try await exposureMirrorStore.mirrorCloudExposures(cloudExposures, forRollID: rollID)
        } else {
            mirrored = []
        }

        roll = fetchedRoll
        currentSession = fetchedSession
        participants = fetchedParticipants
        mirroredExposures = mirrored.sorted(by: { $0.exposure_number < $1.exposure_number })
    }

    private func synchronizeIfNeeded() async {
        guard pendingSyncExposureCount > 0 else {
            return
        }

        await runSynchronization()
    }

    private func recoverPendingWorkIfNeeded() async {
        if let pendingRecoveryCoordinator {
            await pendingRecoveryCoordinator.recoverPendingWork(forRollID: rollID)
            await load()
        } else {
            await synchronizeIfNeeded()
        }
    }

    private func runSynchronization() async {
        guard let syncRunner, !isSynchronizing else {
            return
        }

        isSynchronizing = true
        lastSyncMessage = nil
        defer { isSynchronizing = false }

        do {
            let summary = try await syncRunner.processPendingExposures(
                forRollID: rollID,
                participantID: isSharedRoll ? currentParticipant?.id : nil
            )
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
