import Foundation

struct V2ExposureSyncRunSummary: Sendable, Equatable {
    let processedExposureIDs: [UUID]
    let syncedExposureIDs: [UUID]
    let failedExposureIDs: [UUID]

    var processedCount: Int { processedExposureIDs.count }
    var syncedCount: Int { syncedExposureIDs.count }
    var failedCount: Int { failedExposureIDs.count }
}

protocol ExposureSyncRunning: Sendable {
    @MainActor
    func processPendingExposures(forRollID rollID: UUID) async throws -> V2ExposureSyncRunSummary

    @MainActor
    func processPendingExposures(forRollID rollID: UUID, participantID: UUID?) async throws -> V2ExposureSyncRunSummary
}

@MainActor
final class V2ExposureSyncRunner: ExposureSyncRunning {
    private let exposureMirrorStore: any ExposureMirrorStore
    private let uploadStage: any ExposureUploadStageSyncing
    private let metadataStage: any ExposureMetadataStageSyncing
    private var activeRollIDs: Set<UUID> = []

    init(
        exposureMirrorStore: any ExposureMirrorStore,
        uploadStage: any ExposureUploadStageSyncing,
        metadataStage: any ExposureMetadataStageSyncing
    ) {
        self.exposureMirrorStore = exposureMirrorStore
        self.uploadStage = uploadStage
        self.metadataStage = metadataStage
    }

    func processPendingExposures(forRollID rollID: UUID) async throws -> V2ExposureSyncRunSummary {
        try await processPendingExposures(forRollID: rollID, participantID: nil)
    }

    func processPendingExposures(
        forRollID rollID: UUID,
        participantID: UUID?
    ) async throws -> V2ExposureSyncRunSummary {
        guard !activeRollIDs.contains(rollID) else {
            return V2ExposureSyncRunSummary(
                processedExposureIDs: [],
                syncedExposureIDs: [],
                failedExposureIDs: []
            )
        }

        activeRollIDs.insert(rollID)
        defer { activeRollIDs.remove(rollID) }

        let exposures = try await exposureMirrorStore.fetchExposures(forRollID: rollID)
            .filter { exposure in
                guard let participantID else {
                    return true
                }

                return exposure.participant_id == participantID
            }
            .sorted { $0.exposure_number < $1.exposure_number }

        var processedExposureIDs: [UUID] = []
        var syncedExposureIDs: [UUID] = []
        var failedExposureIDs: [UUID] = []

        for exposure in exposures {
            guard shouldProcess(exposure) else {
                continue
            }

            processedExposureIDs.append(exposure.id)

            do {
                try await process(exposure, forRollID: rollID)
                if exposure.sync_state == .synced {
                    syncedExposureIDs.append(exposure.id)
                }
            } catch {
                failedExposureIDs.append(exposure.id)
                try await markFailed(exposure, error: error)
            }
        }

        return V2ExposureSyncRunSummary(
            processedExposureIDs: processedExposureIDs,
            syncedExposureIDs: syncedExposureIDs,
            failedExposureIDs: failedExposureIDs
        )
    }

    private func shouldProcess(_ exposure: LocalExposure) -> Bool {
        switch exposure.sync_state {
        case .empty, .synced:
            return false
        case .localOnly, .uploading, .metadataPending, .failed:
            return true
        }
    }

    private func process(_ exposure: LocalExposure, forRollID rollID: UUID) async throws {
        switch exposure.sync_state {
        case .localOnly, .uploading:
            try await uploadStage.processUploadStage(for: exposure, rollID: rollID)
            try await metadataStage.processMetadataStage(for: exposure)
        case .metadataPending:
            try await metadataStage.processMetadataStage(for: exposure)
        case .failed:
            if hasCloudStoragePath(exposure) {
                exposure.sync_state = .metadataPending
                exposure.updated_at = Date.now
                try await exposureMirrorStore.saveExposure(exposure)
                try await metadataStage.processMetadataStage(for: exposure)
            } else {
                exposure.sync_state = .localOnly
                exposure.updated_at = Date.now
                try await exposureMirrorStore.saveExposure(exposure)
                try await uploadStage.processUploadStage(for: exposure, rollID: rollID)
                try await metadataStage.processMetadataStage(for: exposure)
            }
        case .empty, .synced:
            break
        }
    }

    private func markFailed(_ exposure: LocalExposure, error: Error) async throws {
        let failedAt = Date.now
        exposure.sync_state = .failed
        exposure.last_error = error.localizedDescription
        exposure.updated_at = failedAt
        try await exposureMirrorStore.saveExposure(exposure)
    }

    private func hasCloudStoragePath(_ exposure: LocalExposure) -> Bool {
        guard let cloudStoragePath = exposure.cloud_storage_path else {
            return false
        }

        return !cloudStoragePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
