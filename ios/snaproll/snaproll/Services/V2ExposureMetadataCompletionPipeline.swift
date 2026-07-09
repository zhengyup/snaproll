import Foundation

struct V2ExposureMetadataCompletionSummary: Sendable, Equatable {
    let syncedExposureIDs: [UUID]
    let failedExposureIDs: [UUID]

    var syncedCount: Int { syncedExposureIDs.count }
    var failedCount: Int { failedExposureIDs.count }
}

enum V2ExposureMetadataCompletionError: LocalizedError {
    case missingCloudStoragePath

    var errorDescription: String? {
        switch self {
        case .missingCloudStoragePath:
            return "The canonical cloud storage path is missing for this exposure."
        }
    }
}

protocol ExposureMetadataCompleting: Sendable {
    @MainActor
    func completePendingMetadata(forRollID rollID: UUID) async throws -> V2ExposureMetadataCompletionSummary
}

protocol ExposureMetadataStageSyncing: Sendable {
    @MainActor
    func processMetadataStage(for exposure: LocalExposure) async throws
}

@MainActor
final class V2ExposureMetadataCompletionPipeline: ExposureMetadataCompleting, ExposureMetadataStageSyncing {
    private let exposureMirrorStore: any ExposureMirrorStore
    private let exposureRepository: any ExposureRepository

    init(
        exposureMirrorStore: any ExposureMirrorStore,
        exposureRepository: any ExposureRepository
    ) {
        self.exposureMirrorStore = exposureMirrorStore
        self.exposureRepository = exposureRepository
    }

    func completePendingMetadata(forRollID rollID: UUID) async throws -> V2ExposureMetadataCompletionSummary {
        let exposures = try await exposureMirrorStore.fetchExposures(forRollID: rollID)
            .sorted { $0.exposure_number < $1.exposure_number }

        var syncedExposureIDs: [UUID] = []
        var failedExposureIDs: [UUID] = []

        for exposure in exposures where exposure.sync_state == .metadataPending {
            do {
                try await completeMetadata(for: exposure)
                syncedExposureIDs.append(exposure.id)
            } catch {
                let failedAt = Date.now
                exposure.sync_state = .metadataPending
                exposure.last_error = error.localizedDescription
                exposure.updated_at = failedAt
                try await exposureMirrorStore.saveExposure(exposure)
                failedExposureIDs.append(exposure.id)
            }
        }

        return V2ExposureMetadataCompletionSummary(
            syncedExposureIDs: syncedExposureIDs,
            failedExposureIDs: failedExposureIDs
        )
    }

    func processMetadataStage(for exposure: LocalExposure) async throws {
        guard let cloudStoragePath = exposure.cloud_storage_path,
              !cloudStoragePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw V2ExposureMetadataCompletionError.missingCloudStoragePath
        }

        _ = try await exposureRepository.completeExposure(
            id: exposure.id,
            storagePath: cloudStoragePath
        )

        let syncedAt = Date.now
        exposure.sync_state = .synced
        exposure.last_error = nil
        exposure.updated_at = syncedAt
        try await exposureMirrorStore.saveExposure(exposure)
    }

    private func completeMetadata(for exposure: LocalExposure) async throws {
        try await processMetadataStage(for: exposure)
    }
}
