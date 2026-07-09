import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2ExposureMetadataCompletionPipelineTests {
    @Test
    func metadataPendingExposureCallsCompleteExposureAndTransitionsToSynced() async throws {
        let rollID = UUID(uuidString: "80808080-0000-0000-0000-000000000001")!
        let exposureID = UUID(uuidString: "80808080-0000-0000-0000-000000000101")!
        let storagePath = "rolls/80808080-0000-0000-0000-000000000001/participants/80808080-0000-0000-0000-000000000201/001.jpg"

        let exposure = makeMetadataExposure(
            id: exposureID,
            rollID: rollID,
            participantID: UUID(uuidString: "80808080-0000-0000-0000-000000000201")!,
            exposureNumber: 1
        )
        exposure.sync_state = .metadataPending
        exposure.cloud_storage_path = storagePath
        exposure.uploaded_at = .now

        let mirrorStore = MetadataCompletionMirrorStore(initialExposures: [rollID: [exposure]])
        let exposureRepository = RecordingMetadataCompletionExposureRepository()
        let pipeline = V2ExposureMetadataCompletionPipeline(
            exposureMirrorStore: mirrorStore,
            exposureRepository: exposureRepository
        )

        let summary = try await pipeline.completePendingMetadata(forRollID: rollID)
        let updated = try await mirrorStore.fetchExposures(forRollID: rollID)
        let syncedExposure = try #require(updated.first)
        let requests = await exposureRepository.completedRequests
        let firstRequest = try #require(requests.first)

        #expect(summary.syncedCount == 1)
        #expect(summary.failedCount == 0)
        #expect(requests.count == 1)
        #expect(firstRequest.0 == exposureID)
        #expect(firstRequest.1 == storagePath)
        #expect(syncedExposure.sync_state == .synced)
        #expect(syncedExposure.cloud_storage_path == storagePath)
        #expect(syncedExposure.last_error == nil)
    }

    @Test
    func metadataCompletionFailurePreservesRetryableStateAndDoesNotReupload() async throws {
        let rollID = UUID(uuidString: "81818181-0000-0000-0000-000000000001")!
        let exposureID = UUID(uuidString: "81818181-0000-0000-0000-000000000101")!
        let storagePath = "rolls/81818181-0000-0000-0000-000000000001/participants/81818181-0000-0000-0000-000000000201/001.jpg"

        let exposure = makeMetadataExposure(
            id: exposureID,
            rollID: rollID,
            participantID: UUID(uuidString: "81818181-0000-0000-0000-000000000201")!,
            exposureNumber: 1
        )
        exposure.sync_state = .metadataPending
        exposure.cloud_storage_path = storagePath

        let mirrorStore = MetadataCompletionMirrorStore(initialExposures: [rollID: [exposure]])
        let exposureRepository = RecordingMetadataCompletionExposureRepository(shouldFail: true)
        let pipeline = V2ExposureMetadataCompletionPipeline(
            exposureMirrorStore: mirrorStore,
            exposureRepository: exposureRepository
        )

        let summary = try await pipeline.completePendingMetadata(forRollID: rollID)
        let updated = try await mirrorStore.fetchExposures(forRollID: rollID)
        let failedExposure = try #require(updated.first)
        let requests = await exposureRepository.completedRequests
        let firstRequest = try #require(requests.first)

        #expect(summary.syncedCount == 0)
        #expect(summary.failedCount == 1)
        #expect(requests.count == 1)
        #expect(firstRequest.0 == exposureID)
        #expect(firstRequest.1 == storagePath)
        #expect(failedExposure.sync_state == .metadataPending)
        #expect(failedExposure.cloud_storage_path == storagePath)
        #expect(failedExposure.last_error != nil)
    }

    @Test
    func metadataCompletionDoesNotProcessNonMetadataPendingExposures() async throws {
        let rollID = UUID(uuidString: "82828282-0000-0000-0000-000000000001")!
        let exposure = makeMetadataExposure(
            id: UUID(uuidString: "82828282-0000-0000-0000-000000000101")!,
            rollID: rollID,
            participantID: UUID(uuidString: "82828282-0000-0000-0000-000000000201")!,
            exposureNumber: 1
        )
        exposure.sync_state = .localOnly

        let mirrorStore = MetadataCompletionMirrorStore(initialExposures: [rollID: [exposure]])
        let exposureRepository = RecordingMetadataCompletionExposureRepository()
        let pipeline = V2ExposureMetadataCompletionPipeline(
            exposureMirrorStore: mirrorStore,
            exposureRepository: exposureRepository
        )

        let summary = try await pipeline.completePendingMetadata(forRollID: rollID)

        #expect(summary.syncedCount == 0)
        #expect(summary.failedCount == 0)
        #expect(await exposureRepository.completedRequests.isEmpty)
    }
}

@MainActor
private final class MetadataCompletionMirrorStore: ExposureMirrorStore {
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

private actor RecordingMetadataCompletionExposureRepository: ExposureRepository {
    private(set) var completedRequests: [(UUID, String)] = []
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] { [] }
    func fetchExposures(forParticipantID participantID: UUID) async throws -> [LocalExposure] { [] }
    func fetchExposure(id: UUID) async throws -> LocalExposure? { nil }

    func completeExposure(id: UUID, storagePath: String) async throws -> CompleteExposureResult {
        completedRequests.append((id, storagePath))
        if shouldFail {
            throw NSError(domain: "MetadataCompletionFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated metadata completion failure"])
        }

        return CompleteExposureResult(participantFinished: false, rollReadyToReveal: false)
    }

    func saveExposure(_ exposure: LocalExposure) async throws {}
    func saveExposures(_ exposures: [LocalExposure]) async throws {}
}

private func makeMetadataExposure(
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
        render_seed: "metadata-seed-\(exposureNumber)",
        sync_state: .empty,
        updated_at: .now
    )
}
