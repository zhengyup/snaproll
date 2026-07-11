import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2ExposureUploadPipelineTests {
    @Test
    func successfulUploadGeneratesJPEGAndTransitionsToMetadataPending() async throws {
        let rollID = UUID(uuidString: "50505050-0000-0000-0000-000000000001")!
        let exposureID = UUID(uuidString: "50505050-0000-0000-0000-000000000101")!
        let participantID = UUID(uuidString: "50505050-0000-0000-0000-000000000201")!
        let storageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let photoStorage = PhotoStorageService(storageRootDirectoryURL: storageRoot)
        let originalURL = try photoStorage.saveOriginalImageData(
            samplePNGData(),
            for: rollID,
            exposureID: exposureID,
            preferredFileExtension: "png"
        )

        let exposure = makeUploadExposure(
            id: exposureID,
            rollID: rollID,
            participantID: participantID,
            exposureNumber: 1
        )
        exposure.local_original_path = photoStorage.persistentLocalPath(for: originalURL)
        exposure.captured_at = .now
        exposure.sync_state = .localOnly

        let mirrorStore = UploadMirrorStore(initialExposures: [rollID: [exposure]])
        let storageRepository = RecordingExposureAssetStorageRepository()
        let pipeline = V2ExposureUploadPipeline(
            exposureMirrorStore: mirrorStore,
            photoStorageService: photoStorage,
            storageRepository: storageRepository
        )

        let summary = try await pipeline.uploadPendingExposures(forRollID: rollID)
        let updated = try await mirrorStore.fetchExposures(forRollID: rollID)
        let uploaded = try #require(updated.first)

        #expect(summary.uploadedCount == 1)
        #expect(summary.failedCount == 0)
        #expect(await storageRepository.uploadedPaths == [uploaded.canonicalCloudStoragePath])
        #expect(uploaded.sync_state == .metadataPending)
        #expect(uploaded.cloud_storage_path == uploaded.canonicalCloudStoragePath)
        #expect(uploaded.uploaded_at != nil)
        #expect(uploaded.upload_jpeg_path != nil)

        if let uploadJPEGPath = uploaded.upload_jpeg_path,
           let uploadData = photoStorage.loadData(at: uploadJPEGPath) {
            #expect(uploadData.starts(with: [0xFF, 0xD8, 0xFF]))
        } else {
            Issue.record("Expected upload JPEG data to be persisted locally.")
        }
    }

    @Test
    func canonicalStoragePathUsesPaddedExposureNumber() async {
        let path = LocalExposure.canonicalCloudStoragePath(
            rollID: UUID(uuidString: "60606060-0000-0000-0000-000000000001")!,
            participantID: UUID(uuidString: "60606060-0000-0000-0000-000000000002")!,
            exposureNumber: 7
        )

        #expect(path.hasSuffix("/007.jpg"))
    }

    @Test
    func uploadFailurePreservesOriginalAndLeavesExposureRetryable() async throws {
        let rollID = UUID(uuidString: "70707070-0000-0000-0000-000000000001")!
        let exposureID = UUID(uuidString: "70707070-0000-0000-0000-000000000101")!
        let participantID = UUID(uuidString: "70707070-0000-0000-0000-000000000201")!
        let storageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let photoStorage = PhotoStorageService(storageRootDirectoryURL: storageRoot)
        let originalURL = try photoStorage.saveOriginalImageData(
            samplePNGData(),
            for: rollID,
            exposureID: exposureID,
            preferredFileExtension: "png"
        )
        let originalPath = photoStorage.persistentLocalPath(for: originalURL)
        let originalDataBeforeFailure = try #require(photoStorage.loadData(at: originalPath))

        let exposure = makeUploadExposure(
            id: exposureID,
            rollID: rollID,
            participantID: participantID,
            exposureNumber: 2
        )
        exposure.local_original_path = originalPath
        exposure.captured_at = .now
        exposure.sync_state = .localOnly

        let mirrorStore = UploadMirrorStore(initialExposures: [rollID: [exposure]])
        let pipeline = V2ExposureUploadPipeline(
            exposureMirrorStore: mirrorStore,
            photoStorageService: photoStorage,
            storageRepository: RecordingExposureAssetStorageRepository(shouldFail: true)
        )

        let summary = try await pipeline.uploadPendingExposures(forRollID: rollID)
        let updated = try await mirrorStore.fetchExposures(forRollID: rollID)
        let failedExposure = try #require(updated.first)
        let originalDataAfterFailure = try #require(photoStorage.loadData(at: originalPath))

        #expect(summary.uploadedCount == 0)
        #expect(summary.failedCount == 1)
        #expect(failedExposure.sync_state == .localOnly)
        #expect(failedExposure.cloud_storage_path == nil)
        #expect(failedExposure.uploaded_at == nil)
        #expect(failedExposure.last_error != nil)
        #expect(originalDataBeforeFailure == originalDataAfterFailure)
    }
}

@MainActor
private final class UploadMirrorStore: ExposureMirrorStore {
    private var exposuresByRollID: [UUID: [LocalExposure]]

    init(initialExposures: [UUID: [LocalExposure]]) {
        self.exposuresByRollID = initialExposures
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] ?? []
    }

    func mirrorCloudExposures(_ exposures: [LocalExposure], forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] = exposures
        return exposures
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

private actor RecordingExposureAssetStorageRepository: ExposureAssetStorageRepository {
    private(set) var uploadedPaths: [String] = []
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func uploadJPEG(data: Data, to storagePath: String) async throws {
        if shouldFail {
            throw NSError(domain: "UploadFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated upload failure"])
        }

        uploadedPaths.append(storagePath)
    }

    func downloadJPEG(from storagePath: String) async throws -> Data {
        Data()
    }
}

private func makeUploadExposure(
    id: UUID,
    rollID: UUID,
    participantID: UUID,
    exposureNumber: Int
) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: participantID,
        exposure_number: exposureNumber,
        render_seed: "upload-seed-\(exposureNumber)",
        sync_state: .empty,
        updated_at: .now
    )
}

private func samplePNGData() -> Data {
    let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9l9QAAAABJRU5ErkJggg=="
    return Data(base64Encoded: base64)!
}
