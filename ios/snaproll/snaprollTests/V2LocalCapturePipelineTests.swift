import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2LocalCapturePipelineTests {
    @Test
    func imageSourceProviderFeedsPipelineAndMarksExposureLocalOnly() async throws {
        let rollID = UUID(uuidString: "10101010-0000-0000-0000-000000000001")!
        let exposure = makeTestExposure(
            id: UUID(uuidString: "10101010-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1
        )
        let store = CaptureMirrorStore(initialExposures: [rollID: [exposure]])
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("v2-capture")
        let storage = PhotoStorageService(fileManager: .default)
        let pipeline = V2LocalCapturePipeline(
            exposureMirrorStore: store,
            photoStorageService: storage
        )
        let provider = FakeImageSourceProvider(data: samplePNGData(), fileExtension: "png")

        let result = try await pipeline.captureNextExposure(forRollID: rollID, using: provider)
        let updated = try await store.fetchExposures(forRollID: rollID)

        #expect(result.exposureNumber == 1)
        #expect(await provider.captureCallCount == 1)
        #expect(updated.first?.sync_state == .localOnly)
        #expect(updated.first?.captured_at != nil)
        #expect(updated.first?.local_original_path != nil)
        if let localPath = updated.first?.local_original_path {
            #expect(storage.fileExists(at: localPath))
        } else {
            Issue.record("Expected local path to be set.")
        }

        _ = tempURL
    }

    @Test
    func sequentialCapturesFillNextEmptyExposureOnly() async throws {
        let rollID = UUID(uuidString: "20202020-0000-0000-0000-000000000001")!
        let exposures = [
            makeTestExposure(id: UUID(), rollID: rollID, exposureNumber: 1),
            makeTestExposure(id: UUID(), rollID: rollID, exposureNumber: 2),
            makeTestExposure(id: UUID(), rollID: rollID, exposureNumber: 3)
        ]
        let store = CaptureMirrorStore(initialExposures: [rollID: exposures])
        let pipeline = V2LocalCapturePipeline(
            exposureMirrorStore: store,
            photoStorageService: PhotoStorageService()
        )

        _ = try await pipeline.captureNextExposure(
            forRollID: rollID,
            using: FakeImageSourceProvider(data: samplePNGData(), fileExtension: "png")
        )
        _ = try await pipeline.captureNextExposure(
            forRollID: rollID,
            using: FakeImageSourceProvider(data: samplePNGData(), fileExtension: "png")
        )

        let updated = try await store.fetchExposures(forRollID: rollID)
        #expect(updated[0].sync_state == .localOnly)
        #expect(updated[1].sync_state == .localOnly)
        #expect(updated[2].sync_state == .empty)
        #expect(updated[0].local_original_path != nil)
        #expect(updated[1].local_original_path != nil)
        #expect(updated[2].local_original_path == nil)
    }

    @Test
    func captureDoesNotOverwriteExistingExposure() async throws {
        let rollID = UUID(uuidString: "30303030-0000-0000-0000-000000000001")!
        let filled = makeTestExposure(id: UUID(), rollID: rollID, exposureNumber: 1)
        filled.local_original_path = "existing/path.jpg"
        filled.captured_at = .now
        filled.sync_state = .localOnly
        let empty = makeTestExposure(id: UUID(), rollID: rollID, exposureNumber: 2)
        let store = CaptureMirrorStore(initialExposures: [rollID: [filled, empty]])
        let pipeline = V2LocalCapturePipeline(
            exposureMirrorStore: store,
            photoStorageService: PhotoStorageService()
        )

        let result = try await pipeline.captureNextExposure(
            forRollID: rollID,
            using: FakeImageSourceProvider(data: samplePNGData(), fileExtension: "png")
        )
        let updated = try await store.fetchExposures(forRollID: rollID)

        #expect(result.exposureNumber == 2)
        #expect(updated[0].local_original_path == "existing/path.jpg")
        #expect(updated[1].sync_state == .localOnly)
    }

    @Test
    func noRemainingExposureThrowsAndDoesNotCapture() async {
        let rollID = UUID(uuidString: "40404040-0000-0000-0000-000000000001")!
        let filled = makeTestExposure(id: UUID(), rollID: rollID, exposureNumber: 1)
        filled.local_original_path = "existing/path.jpg"
        filled.captured_at = .now
        filled.sync_state = .localOnly
        let store = CaptureMirrorStore(initialExposures: [rollID: [filled]])
        let provider = FakeImageSourceProvider(data: samplePNGData(), fileExtension: "png")
        let pipeline = V2LocalCapturePipeline(
            exposureMirrorStore: store,
            photoStorageService: PhotoStorageService()
        )

        await #expect(throws: V2LocalCapturePipelineError.self) {
            try await pipeline.captureNextExposure(forRollID: rollID, using: provider)
        }
        #expect(await provider.captureCallCount == 1)
    }
}

@MainActor
private final class CaptureMirrorStore: ExposureMirrorStore {
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

private actor FakeImageSourceProvider: ImageSourceProvider {
    let kind: V2ImageSourceKind = .developmentSample
    private let data: Data
    private let fileExtension: String
    private(set) var captureCallCount = 0

    init(data: Data, fileExtension: String) {
        self.data = data
        self.fileExtension = fileExtension
    }

    func captureImage() async throws -> CapturedImagePayload {
        captureCallCount += 1
        return CapturedImagePayload(data: data, fileExtension: fileExtension)
    }
}

private func makeTestExposure(id: UUID, rollID: UUID, exposureNumber: Int) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
        exposure_number: exposureNumber,
        render_seed: "seed-\(exposureNumber)",
        sync_state: .empty,
        updated_at: .now
    )
}

private func samplePNGData() -> Data {
    let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9l9QAAAABJRU5ErkJggg=="
    return Data(base64Encoded: base64)!
}
