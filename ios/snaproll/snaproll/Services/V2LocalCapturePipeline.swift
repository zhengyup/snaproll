import Foundation

struct V2CaptureResult: Sendable {
    let capturedExposureID: UUID
    let exposureNumber: Int
    let localOriginalPath: String
}

enum V2LocalCapturePipelineError: LocalizedError {
    case noRemainingExposures
    case captureFailedToPersist

    var errorDescription: String? {
        switch self {
        case .noRemainingExposures:
            return "This roll has no remaining empty exposures."
        case .captureFailedToPersist:
            return "The captured image could not be saved locally."
        }
    }
}

@MainActor
final class V2LocalCapturePipeline {
    private let exposureMirrorStore: any ExposureMirrorStore
    private let photoStorageService: PhotoStorageService

    init(
        exposureMirrorStore: any ExposureMirrorStore,
        photoStorageService: PhotoStorageService
    ) {
        self.exposureMirrorStore = exposureMirrorStore
        self.photoStorageService = photoStorageService
    }

    func captureNextExposure(
        forRollID rollID: UUID,
        participantID: UUID? = nil,
        using provider: any ImageSourceProvider
    ) async throws -> V2CaptureResult {
        let payload = try await provider.captureImage()
        let exposures = try await exposureMirrorStore.fetchExposures(forRollID: rollID)
            .filter { exposure in
                guard let participantID else {
                    return true
                }

                return exposure.participant_id == participantID
            }
            .sorted { $0.exposure_number < $1.exposure_number }

        guard let targetExposure = exposures.first(where: Self.isEmptyExposure) else {
            throw V2LocalCapturePipelineError.noRemainingExposures
        }

        let savedURL: URL
        do {
            savedURL = try photoStorageService.saveOriginalImageData(
                payload.data,
                for: rollID,
                exposureID: targetExposure.id,
                preferredFileExtension: payload.fileExtension
            )
        } catch {
            throw V2LocalCapturePipelineError.captureFailedToPersist
        }

        let now = Date.now
        targetExposure.local_original_path = photoStorageService.persistentLocalPath(for: savedURL)
        targetExposure.captured_at = now
        targetExposure.sync_state = .localOnly
        targetExposure.last_error = nil
        targetExposure.updated_at = now

        try await exposureMirrorStore.saveExposure(targetExposure)

        return V2CaptureResult(
            capturedExposureID: targetExposure.id,
            exposureNumber: targetExposure.exposure_number,
            localOriginalPath: targetExposure.local_original_path ?? savedURL.path
        )
    }

    static func isEmptyExposure(_ exposure: LocalExposure) -> Bool {
        exposure.local_original_path == nil
            && exposure.cloud_storage_path == nil
            && exposure.captured_at == nil
            && exposure.sync_state == .empty
    }
}
