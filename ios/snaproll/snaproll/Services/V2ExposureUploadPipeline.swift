import Foundation

struct V2ExposureUploadSummary: Sendable, Equatable {
    let uploadedExposureIDs: [UUID]
    let failedExposureIDs: [UUID]

    var uploadedCount: Int { uploadedExposureIDs.count }
    var failedCount: Int { failedExposureIDs.count }
}

enum V2ExposureUploadPipelineError: LocalizedError {
    case missingLocalOriginal

    var errorDescription: String? {
        switch self {
        case .missingLocalOriginal:
            return "The local original image is missing for this exposure."
        }
    }
}

protocol ExposureUploadSyncing: Sendable {
    @MainActor
    func uploadPendingExposures(forRollID rollID: UUID) async throws -> V2ExposureUploadSummary
}

@MainActor
final class V2ExposureUploadPipeline: ExposureUploadSyncing {
    private let exposureMirrorStore: any ExposureMirrorStore
    private let photoStorageService: PhotoStorageService
    private let storageRepository: any ExposureAssetStorageRepository

    init(
        exposureMirrorStore: any ExposureMirrorStore,
        photoStorageService: PhotoStorageService,
        storageRepository: any ExposureAssetStorageRepository
    ) {
        self.exposureMirrorStore = exposureMirrorStore
        self.photoStorageService = photoStorageService
        self.storageRepository = storageRepository
    }

    func uploadPendingExposures(forRollID rollID: UUID) async throws -> V2ExposureUploadSummary {
        let exposures = try await exposureMirrorStore.fetchExposures(forRollID: rollID)
            .sorted { $0.exposure_number < $1.exposure_number }

        var uploadedExposureIDs: [UUID] = []
        var failedExposureIDs: [UUID] = []

        for exposure in exposures where exposure.sync_state == .localOnly {
            do {
                try await upload(exposure, forRollID: rollID)
                uploadedExposureIDs.append(exposure.id)
            } catch {
                let now = Date.now
                exposure.sync_state = .localOnly
                exposure.last_error = error.localizedDescription
                exposure.updated_at = now
                try await exposureMirrorStore.saveExposure(exposure)
                failedExposureIDs.append(exposure.id)
            }
        }

        return V2ExposureUploadSummary(
            uploadedExposureIDs: uploadedExposureIDs,
            failedExposureIDs: failedExposureIDs
        )
    }

    private func upload(_ exposure: LocalExposure, forRollID rollID: UUID) async throws {
        guard let localOriginalPath = exposure.local_original_path,
              photoStorageService.fileExists(at: localOriginalPath) else {
            throw V2ExposureUploadPipelineError.missingLocalOriginal
        }

        let uploadStartedAt = Date.now
        exposure.sync_state = .uploading
        exposure.last_error = nil
        exposure.updated_at = uploadStartedAt
        try await exposureMirrorStore.saveExposure(exposure)

        let uploadJPEGData = try photoStorageService.makeUploadJPEGData(from: localOriginalPath)
        let uploadJPEGURL = try photoStorageService.saveUploadJPEGData(
            uploadJPEGData,
            for: rollID,
            exposureID: exposure.id
        )
        let uploadJPEGPath = photoStorageService.persistentLocalPath(for: uploadJPEGURL)
        let storagePath = exposure.canonicalCloudStoragePath

        exposure.upload_jpeg_path = uploadJPEGPath
        exposure.updated_at = Date.now
        try await exposureMirrorStore.saveExposure(exposure)

        try await storageRepository.uploadJPEG(data: uploadJPEGData, to: storagePath)

        let uploadedAt = Date.now
        exposure.upload_jpeg_path = uploadJPEGPath
        exposure.cloud_storage_path = storagePath
        exposure.uploaded_at = uploadedAt
        exposure.sync_state = .metadataPending
        exposure.last_error = nil
        exposure.updated_at = uploadedAt
        try await exposureMirrorStore.saveExposure(exposure)
    }
}
