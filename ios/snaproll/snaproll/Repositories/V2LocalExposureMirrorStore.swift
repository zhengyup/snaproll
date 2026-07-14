import Foundation

private struct LocalExposureSnapshot: Codable, Sendable {
    let id: UUID
    let ownerUserID: UUID?
    let rollID: UUID
    let participantID: UUID
    let exposureNumber: Int
    let renderSeed: String
    let localOriginalPath: String?
    let uploadJPEGPath: String?
    let cloudStoragePath: String?
    let renderedCachePath: String?
    let syncState: V2Domain.ExposureSyncState
    let capturedAt: Date?
    let uploadedAt: Date?
    let lastError: String?
    let lastRecoveryFromState: String?
    let lastRecoveryToState: String?
    let lastRecoveryReason: String?
    let lastRecoveryError: String?
    let lastRecoveredAt: Date?
    let lastReconciliationRule: String?
    let lastReconciliationError: String?
    let lastReconciledAt: Date?
    let updatedAt: Date

    init(
        id: UUID,
        ownerUserID: UUID?,
        rollID: UUID,
        participantID: UUID,
        exposureNumber: Int,
        renderSeed: String,
        localOriginalPath: String?,
        uploadJPEGPath: String?,
        cloudStoragePath: String?,
        renderedCachePath: String?,
        syncState: V2Domain.ExposureSyncState,
        capturedAt: Date?,
        uploadedAt: Date?,
        lastError: String?,
        lastRecoveryFromState: String?,
        lastRecoveryToState: String?,
        lastRecoveryReason: String?,
        lastRecoveryError: String?,
        lastRecoveredAt: Date?,
        lastReconciliationRule: String?,
        lastReconciliationError: String?,
        lastReconciledAt: Date?,
        updatedAt: Date
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.rollID = rollID
        self.participantID = participantID
        self.exposureNumber = exposureNumber
        self.renderSeed = renderSeed
        self.localOriginalPath = localOriginalPath
        self.uploadJPEGPath = uploadJPEGPath
        self.cloudStoragePath = cloudStoragePath
        self.renderedCachePath = renderedCachePath
        self.syncState = syncState
        self.capturedAt = capturedAt
        self.uploadedAt = uploadedAt
        self.lastError = lastError
        self.lastRecoveryFromState = lastRecoveryFromState
        self.lastRecoveryToState = lastRecoveryToState
        self.lastRecoveryReason = lastRecoveryReason
        self.lastRecoveryError = lastRecoveryError
        self.lastRecoveredAt = lastRecoveredAt
        self.lastReconciliationRule = lastReconciliationRule
        self.lastReconciliationError = lastReconciliationError
        self.lastReconciledAt = lastReconciledAt
        self.updatedAt = updatedAt
    }

    init(exposure: LocalExposure) {
        self.id = exposure.id
        self.ownerUserID = exposure.owner_user_id
        self.rollID = exposure.roll_id
        self.participantID = exposure.participant_id
        self.exposureNumber = exposure.exposure_number
        self.renderSeed = exposure.render_seed
        self.localOriginalPath = exposure.local_original_path
        self.uploadJPEGPath = exposure.upload_jpeg_path
        self.cloudStoragePath = exposure.cloud_storage_path
        self.renderedCachePath = exposure.rendered_cache_path
        self.syncState = exposure.sync_state
        self.capturedAt = exposure.captured_at
        self.uploadedAt = exposure.uploaded_at
        self.lastError = exposure.last_error
        self.lastRecoveryFromState = exposure.last_recovery_from_state
        self.lastRecoveryToState = exposure.last_recovery_to_state
        self.lastRecoveryReason = exposure.last_recovery_reason
        self.lastRecoveryError = exposure.last_recovery_error
        self.lastRecoveredAt = exposure.last_recovered_at
        self.lastReconciliationRule = exposure.last_reconciliation_rule
        self.lastReconciliationError = exposure.last_reconciliation_error
        self.lastReconciledAt = exposure.last_reconciled_at
        self.updatedAt = exposure.updated_at
    }

    func toLocalExposure() -> LocalExposure {
        LocalExposure(
            id: id,
            owner_user_id: ownerUserID,
            roll_id: rollID,
            participant_id: participantID,
            exposure_number: exposureNumber,
            render_seed: renderSeed,
            local_original_path: localOriginalPath,
            upload_jpeg_path: uploadJPEGPath,
            cloud_storage_path: cloudStoragePath,
            rendered_cache_path: renderedCachePath,
            sync_state: syncState,
            captured_at: capturedAt,
            uploaded_at: uploadedAt,
            last_error: lastError,
            last_recovery_from_state: lastRecoveryFromState,
            last_recovery_to_state: lastRecoveryToState,
            last_recovery_reason: lastRecoveryReason,
            last_recovery_error: lastRecoveryError,
            last_recovered_at: lastRecoveredAt,
            last_reconciliation_rule: lastReconciliationRule,
            last_reconciliation_error: lastReconciliationError,
            last_reconciled_at: lastReconciledAt,
            updated_at: updatedAt
        )
    }
}

@MainActor
final class FileBackedExposureMirrorStore: ExposureMirrorStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var hasLoaded = false
    private var snapshotsByID: [UUID: LocalExposureSnapshot] = [:]

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL()
        }

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        try loadIfNeeded()

        return snapshotsByID.values
            .filter { $0.rollID == rollID }
            .sorted { lhs, rhs in
                if lhs.exposureNumber == rhs.exposureNumber {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.exposureNumber < rhs.exposureNumber
            }
            .map { $0.toLocalExposure() }
    }

    func mirrorCloudExposures(_ exposures: [LocalExposure], forRollID rollID: UUID) async throws -> [LocalExposure] {
        try loadIfNeeded()

        let existingByID = snapshotsByID
            .values
            .filter { $0.rollID == rollID }
            .reduce(into: [UUID: LocalExposureSnapshot]()) { partialResult, snapshot in
                partialResult[snapshot.id] = snapshot
            }

        let mergedSnapshots = exposures.map { exposure in
            let existing = existingByID[exposure.id]
            return merge(cloud: exposure, existing: existing)
        }

        for snapshot in snapshotsByID.values where snapshot.rollID == rollID {
            snapshotsByID.removeValue(forKey: snapshot.id)
        }

        for snapshot in mergedSnapshots {
            snapshotsByID[snapshot.id] = snapshot
        }

        try persist()
        return mergedSnapshots
            .sorted { $0.exposureNumber < $1.exposureNumber }
            .map { $0.toLocalExposure() }
    }

    func saveExposure(_ exposure: LocalExposure) async throws {
        try loadIfNeeded()
        snapshotsByID[exposure.id] = LocalExposureSnapshot(exposure: exposure)
        try persist()
    }

    private func merge(
        cloud exposure: LocalExposure,
        existing: LocalExposureSnapshot?
    ) -> LocalExposureSnapshot {
        let cloudHasUploadedAsset = exposure.cloud_storage_path != nil
        let mergedSyncState: V2Domain.ExposureSyncState

        if cloudHasUploadedAsset {
            mergedSyncState = .synced
        } else {
            mergedSyncState = existing?.syncState ?? exposure.sync_state
        }

        let id = exposure.id
        let ownerUserID = existing?.ownerUserID
        let rollID = exposure.roll_id
        let participantID = exposure.participant_id
        let exposureNumber = exposure.exposure_number
        let renderSeed = exposure.render_seed
        let cloudStoragePath = exposure.cloud_storage_path ?? existing?.cloudStoragePath
        let capturedAt = existing?.capturedAt ?? exposure.captured_at
        let uploadedAt = exposure.uploaded_at ?? existing?.uploadedAt
        let updatedAt = max(existing?.updatedAt ?? exposure.updated_at, exposure.updated_at)
        let lastError = cloudHasUploadedAsset ? nil : existing?.lastError
        let lastRecoveryFromState = existing?.lastRecoveryFromState
        let lastRecoveryToState = existing?.lastRecoveryToState
        let lastRecoveryReason = existing?.lastRecoveryReason
        let lastRecoveryError = existing?.lastRecoveryError
        let lastRecoveredAt = existing?.lastRecoveredAt
        let lastReconciliationRule = existing?.lastReconciliationRule
        let lastReconciliationError = existing?.lastReconciliationError
        let lastReconciledAt = existing?.lastReconciledAt

        return LocalExposureSnapshot(
            id: id,
            ownerUserID: ownerUserID,
            rollID: rollID,
            participantID: participantID,
            exposureNumber: exposureNumber,
            renderSeed: renderSeed,
            localOriginalPath: existing?.localOriginalPath,
            uploadJPEGPath: existing?.uploadJPEGPath,
            cloudStoragePath: cloudStoragePath,
            renderedCachePath: existing?.renderedCachePath,
            syncState: mergedSyncState,
            capturedAt: capturedAt,
            uploadedAt: uploadedAt,
            lastError: lastError,
            lastRecoveryFromState: lastRecoveryFromState,
            lastRecoveryToState: lastRecoveryToState,
            lastRecoveryReason: lastRecoveryReason,
            lastRecoveryError: lastRecoveryError,
            lastRecoveredAt: lastRecoveredAt,
            lastReconciliationRule: lastReconciliationRule,
            lastReconciliationError: lastReconciliationError,
            lastReconciledAt: lastReconciledAt,
            updatedAt: updatedAt
        )
    }

    private func loadIfNeeded() throws {
        guard !hasLoaded else {
            return
        }

        defer { hasLoaded = true }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            snapshotsByID = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        let snapshots = try decoder.decode([LocalExposureSnapshot].self, from: data)
        snapshotsByID = snapshots.reduce(into: [:]) { partialResult, snapshot in
            partialResult[snapshot.id] = snapshot
        }
    }

    private func persist() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let snapshots = snapshotsByID.values.sorted { lhs, rhs in
            if lhs.rollID == rhs.rollID {
                return lhs.exposureNumber < rhs.exposureNumber
            }

            return lhs.rollID.uuidString < rhs.rollID.uuidString
        }
        let data = try encoder.encode(snapshots)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseDirectory
            .appendingPathComponent("Snaproll", isDirectory: true)
            .appendingPathComponent("v2-local-exposures.json")
    }
}
