import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2ExposureSyncRunnerTests {
    @Test
    func simultaneousSyncRequestsResultInOneActivePass() async throws {
        let rollID = UUID(uuidString: "10101010-0000-0000-0000-000000000001")!
        let exposure = makeRunnerExposure(
            id: UUID(uuidString: "10101010-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .localOnly
        )
        let store = RunnerMirrorStore(initialExposures: [rollID: [exposure]])
        let uploadStage = RecordingUploadStage(
            exposureMirrorStore: store,
            delayNanoseconds: 100_000_000
        )
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let firstTask = Task {
            try await runner.processPendingExposures(forRollID: rollID)
        }
        await Task.yield()
        let duplicateSummary = try await runner.processPendingExposures(forRollID: rollID)
        let firstSummary = try await firstTask.value

        #expect(firstSummary.processedExposureIDs == [exposure.id])
        #expect(duplicateSummary.wasSkippedDueToActiveRun)
        #expect(duplicateSummary.processedCount == 0)
        #expect(await uploadStage.processedExposureIDs == [exposure.id])
    }

    @Test
    func laterRequestCanRunAfterFirstPassFinishes() async throws {
        let rollID = UUID(uuidString: "10101010-0000-0000-0000-000000000002")!
        let exposure = makeRunnerExposure(
            id: UUID(uuidString: "10101010-0000-0000-0000-000000000201")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .localOnly
        )
        let store = RunnerMirrorStore(initialExposures: [rollID: [exposure]])
        let uploadStage = RecordingUploadStage(exposureMirrorStore: store)
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let firstSummary = try await runner.processPendingExposures(forRollID: rollID)
        let secondSummary = try await runner.processPendingExposures(forRollID: rollID)

        #expect(firstSummary.processedCount == 1)
        #expect(!secondSummary.wasSkippedDueToActiveRun)
        #expect(secondSummary.processedCount == 0)
    }

    @Test
    func pendingExposuresAreProcessedSequentiallyByExposureNumber() async throws {
        let rollID = UUID(uuidString: "10101010-0000-0000-0000-000000000003")!
        let firstExposure = makeRunnerExposure(
            id: UUID(uuidString: "10101010-0000-0000-0000-000000000301")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .localOnly
        )
        let secondExposure = makeRunnerExposure(
            id: UUID(uuidString: "10101010-0000-0000-0000-000000000302")!,
            rollID: rollID,
            exposureNumber: 2,
            syncState: .localOnly
        )
        let store = RunnerMirrorStore(initialExposures: [rollID: [secondExposure, firstExposure]])
        let uploadStage = RecordingUploadStage(exposureMirrorStore: store)
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)

        #expect(summary.processedExposureIDs == [firstExposure.id, secondExposure.id])
        #expect(await uploadStage.processedExposureIDs == [firstExposure.id, secondExposure.id])
        #expect(await metadataStage.processedExposureIDs == [firstExposure.id, secondExposure.id])
    }

    @Test
    func localOnlyExposureProgressesToSynced() async throws {
        let rollID = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
        let exposure = makeRunnerExposure(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .localOnly
        )
        let store = RunnerMirrorStore(initialExposures: [rollID: [exposure]])
        let uploadStage = RecordingUploadStage(exposureMirrorStore: store)
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)
        let updated = try await store.fetchExposures(forRollID: rollID)

        #expect(summary.processedCount == 1)
        #expect(summary.syncedCount == 1)
        #expect(summary.failedCount == 0)
        #expect(await uploadStage.processedExposureIDs == [exposure.id])
        #expect(await metadataStage.processedExposureIDs == [exposure.id])
        #expect(updated.first?.sync_state == .synced)
        #expect(updated.first?.cloud_storage_path == exposure.canonicalCloudStoragePath)
    }

    @Test
    func metadataPendingRetriesMetadataOnly() async throws {
        let rollID = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!
        let exposure = makeRunnerExposure(
            id: UUID(uuidString: "22222222-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .metadataPending
        )
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
        let store = RunnerMirrorStore(initialExposures: [rollID: [exposure]])
        let uploadStage = RecordingUploadStage(exposureMirrorStore: store)
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)
        let updated = try await store.fetchExposures(forRollID: rollID)

        #expect(summary.syncedCount == 1)
        #expect(await uploadStage.processedExposureIDs.isEmpty)
        #expect(await metadataStage.processedExposureIDs == [exposure.id])
        #expect(updated.first?.sync_state == .synced)
    }

    @Test
    func failedExposureWithCloudPathRetriesMetadataOnly() async throws {
        let rollID = UUID(uuidString: "33333333-0000-0000-0000-000000000001")!
        let exposure = makeRunnerExposure(
            id: UUID(uuidString: "33333333-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .failed
        )
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
        exposure.last_error = "Upload succeeded, metadata failed"
        let store = RunnerMirrorStore(initialExposures: [rollID: [exposure]])
        let uploadStage = RecordingUploadStage(exposureMirrorStore: store)
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)
        let updated = try await store.fetchExposures(forRollID: rollID)

        #expect(summary.syncedCount == 1)
        #expect(await uploadStage.processedExposureIDs.isEmpty)
        #expect(await metadataStage.processedExposureIDs == [exposure.id])
        #expect(updated.first?.sync_state == .synced)
        #expect(updated.first?.last_error == nil)
    }

    @Test
    func failedExposureWithoutCloudPathRestartsUploadThenMetadata() async throws {
        let rollID = UUID(uuidString: "44444444-0000-0000-0000-000000000001")!
        let exposure = makeRunnerExposure(
            id: UUID(uuidString: "44444444-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .failed
        )
        exposure.last_error = "Network timeout"
        let store = RunnerMirrorStore(initialExposures: [rollID: [exposure]])
        let uploadStage = RecordingUploadStage(exposureMirrorStore: store)
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)
        let updated = try await store.fetchExposures(forRollID: rollID)

        #expect(summary.syncedCount == 1)
        #expect(await uploadStage.processedExposureIDs == [exposure.id])
        #expect(await metadataStage.processedExposureIDs == [exposure.id])
        #expect(updated.first?.sync_state == .synced)
    }

    @Test
    func failedExposureDoesNotPreventLaterExposuresFromSyncing() async throws {
        let rollID = UUID(uuidString: "55555555-0000-0000-0000-000000000001")!
        let firstExposure = makeRunnerExposure(
            id: UUID(uuidString: "55555555-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .localOnly
        )
        let secondExposure = makeRunnerExposure(
            id: UUID(uuidString: "55555555-0000-0000-0000-000000000102")!,
            rollID: rollID,
            exposureNumber: 2,
            syncState: .localOnly
        )
        let store = RunnerMirrorStore(initialExposures: [rollID: [firstExposure, secondExposure]])
        let uploadStage = RecordingUploadStage(
            exposureMirrorStore: store,
            failingExposureIDs: [firstExposure.id]
        )
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)
        let updated = try await store.fetchExposures(forRollID: rollID)

        #expect(summary.processedCount == 2)
        #expect(summary.syncedCount == 1)
        #expect(summary.failedCount == 1)
        #expect(updated[0].sync_state == .failed)
        #expect(updated[1].sync_state == .synced)
        #expect(await uploadStage.processedExposureIDs == [firstExposure.id, firstExposure.id, secondExposure.id])
        #expect(await metadataStage.processedExposureIDs == [secondExposure.id])
    }

    @Test
    func persistedMetadataPendingExposureRecoversAfterRestart() async throws {
        let rollID = UUID(uuidString: "66666666-0000-0000-0000-000000000001")!
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("mirror.json")

        let persistedStore = FileBackedExposureMirrorStore(fileURL: fileURL)
        let exposure = makeRunnerExposure(
            id: UUID(uuidString: "66666666-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .failed
        )
        exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
        exposure.last_error = "Pending metadata completion"
        try await persistedStore.saveExposure(exposure)

        let restartedStore = FileBackedExposureMirrorStore(fileURL: fileURL)
        let uploadStage = RecordingUploadStage(exposureMirrorStore: restartedStore)
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: restartedStore)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: restartedStore,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)
        let updated = try await restartedStore.fetchExposures(forRollID: rollID)

        #expect(summary.syncedCount == 1)
        #expect(await uploadStage.processedExposureIDs.isEmpty)
        #expect(await metadataStage.processedExposureIDs == [exposure.id])
        #expect(updated.first?.sync_state == .synced)
        #expect(updated.first?.cloud_storage_path == exposure.canonicalCloudStoragePath)
    }

    @Test
    func sharedSyncOnlyProcessesCurrentParticipantExposures() async throws {
        let rollID = UUID(uuidString: "77777777-0000-0000-0000-000000000001")!
        let currentParticipantID = UUID(uuidString: "77777777-0000-0000-0000-0000000000A1")!
        let otherParticipantID = UUID(uuidString: "77777777-0000-0000-0000-0000000000B2")!

        let currentExposure = LocalExposure(
            id: UUID(uuidString: "77777777-0000-0000-0000-000000000101")!,
            roll_id: rollID,
            participant_id: currentParticipantID,
            exposure_number: 1,
            render_seed: "current",
            sync_state: .localOnly,
            updated_at: .now
        )
        let otherExposure = LocalExposure(
            id: UUID(uuidString: "77777777-0000-0000-0000-000000000102")!,
            roll_id: rollID,
            participant_id: otherParticipantID,
            exposure_number: 1,
            render_seed: "other",
            sync_state: .localOnly,
            updated_at: .now
        )

        let store = RunnerMirrorStore(initialExposures: [rollID: [currentExposure, otherExposure]])
        let uploadStage = RecordingUploadStage(exposureMirrorStore: store)
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(
            forRollID: rollID,
            participantID: currentParticipantID
        )
        let updated = try await store.fetchExposures(forRollID: rollID)
        let syncedCurrent = updated.first(where: { $0.participant_id == currentParticipantID })
        let untouchedOther = updated.first(where: { $0.participant_id == otherParticipantID })

        #expect(summary.processedExposureIDs == [currentExposure.id])
        #expect(await uploadStage.processedExposureIDs == [currentExposure.id])
        #expect(await metadataStage.processedExposureIDs == [currentExposure.id])
        #expect(syncedCurrent?.sync_state == .synced)
        #expect(untouchedOther?.sync_state == .localOnly)
        #expect(untouchedOther?.cloud_storage_path == nil)
    }

    @Test
    func transientUploadFailureRetriesWithinOneSyncPass() async throws {
        let rollID = UUID(uuidString: "88888888-0000-0000-0000-000000000001")!
        let exposure = makeRunnerExposure(
            id: UUID(uuidString: "88888888-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .localOnly
        )
        let store = RunnerMirrorStore(initialExposures: [rollID: [exposure]])
        let uploadStage = RecordingUploadStage(
            exposureMirrorStore: store,
            transientFailuresByExposureID: [exposure.id: 1]
        )
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)
        let updated = try await store.fetchExposures(forRollID: rollID)

        #expect(summary.syncedCount == 1)
        #expect(summary.failedCount == 0)
        #expect(await uploadStage.processedExposureIDs == [exposure.id, exposure.id])
        #expect(updated.first?.sync_state == .synced)
    }

    @Test
    func exhaustedRetriesPreserveLocalDataAndRetryableState() async throws {
        let rollID = UUID(uuidString: "89898989-0000-0000-0000-000000000001")!
        let exposure = makeRunnerExposure(
            id: UUID(uuidString: "89898989-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .localOnly
        )
        exposure.local_original_path = "/tmp/original.jpg"
        let store = RunnerMirrorStore(initialExposures: [rollID: [exposure]])
        let uploadStage = RecordingUploadStage(
            exposureMirrorStore: store,
            failingExposureIDs: [exposure.id]
        )
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            maxAttemptsPerExposure: 2,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)
        let updated = try await store.fetchExposures(forRollID: rollID)
        let failedExposure = try #require(updated.first)

        #expect(summary.syncedCount == 0)
        #expect(summary.failedCount == 1)
        #expect(await uploadStage.processedExposureIDs == [exposure.id, exposure.id])
        #expect(failedExposure.sync_state == .failed)
        #expect(failedExposure.local_original_path == "/tmp/original.jpg")
        #expect(failedExposure.cloud_storage_path == nil)
        #expect(failedExposure.last_error != nil)
    }

    @Test
    func syncedAndEmptyExposuresAreIgnored() async throws {
        let rollID = UUID(uuidString: "90909090-0000-0000-0000-000000000001")!
        let emptyExposure = makeRunnerExposure(
            id: UUID(uuidString: "90909090-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            syncState: .empty
        )
        let syncedExposure = makeRunnerExposure(
            id: UUID(uuidString: "90909090-0000-0000-0000-000000000102")!,
            rollID: rollID,
            exposureNumber: 2,
            syncState: .synced
        )
        let store = RunnerMirrorStore(initialExposures: [rollID: [emptyExposure, syncedExposure]])
        let uploadStage = RecordingUploadStage(exposureMirrorStore: store)
        let metadataStage = RecordingMetadataStage(exposureMirrorStore: store)
        let runner = V2ExposureSyncRunner(
            exposureMirrorStore: store,
            uploadStage: uploadStage,
            metadataStage: metadataStage,
            retryDelayNanoseconds: 0
        )

        let summary = try await runner.processPendingExposures(forRollID: rollID)

        #expect(summary.processedCount == 0)
        #expect(await uploadStage.processedExposureIDs.isEmpty)
        #expect(await metadataStage.processedExposureIDs.isEmpty)
    }
}

@MainActor
private final class RunnerMirrorStore: ExposureMirrorStore {
    private var exposuresByRollID: [UUID: [LocalExposure]]

    init(initialExposures: [UUID: [LocalExposure]]) {
        self.exposuresByRollID = initialExposures
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        (exposuresByRollID[rollID] ?? []).sorted { $0.exposure_number < $1.exposure_number }
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

private actor RecordingUploadStage: ExposureUploadStageSyncing {
    private(set) var processedExposureIDs: [UUID] = []
    private let exposureMirrorStore: any ExposureMirrorStore
    private let failingExposureIDs: Set<UUID>
    private var transientFailuresByExposureID: [UUID: Int]
    private let delayNanoseconds: UInt64

    init(
        exposureMirrorStore: any ExposureMirrorStore,
        failingExposureIDs: Set<UUID> = [],
        transientFailuresByExposureID: [UUID: Int] = [:],
        delayNanoseconds: UInt64 = 0
    ) {
        self.exposureMirrorStore = exposureMirrorStore
        self.failingExposureIDs = failingExposureIDs
        self.transientFailuresByExposureID = transientFailuresByExposureID
        self.delayNanoseconds = delayNanoseconds
    }

    func processUploadStage(for exposure: LocalExposure, rollID: UUID) async throws {
        let exposureID = await MainActor.run { exposure.id }
        processedExposureIDs.append(exposureID)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        if failingExposureIDs.contains(exposureID) {
            throw NSError(
                domain: "UploadStage",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated upload failure"]
            )
        }
        if let remainingFailures = transientFailuresByExposureID[exposureID], remainingFailures > 0 {
            transientFailuresByExposureID[exposureID] = remainingFailures - 1
            throw NSError(
                domain: "UploadStage",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Simulated transient upload failure"]
            )
        }

        await MainActor.run {
            exposure.sync_state = .metadataPending
            exposure.cloud_storage_path = exposure.canonicalCloudStoragePath
            exposure.uploaded_at = .now
            exposure.last_error = nil
        }
        try await exposureMirrorStore.saveExposure(exposure)
    }
}

private actor RecordingMetadataStage: ExposureMetadataStageSyncing {
    private(set) var processedExposureIDs: [UUID] = []
    private let exposureMirrorStore: any ExposureMirrorStore

    init(exposureMirrorStore: any ExposureMirrorStore) {
        self.exposureMirrorStore = exposureMirrorStore
    }

    func processMetadataStage(for exposure: LocalExposure) async throws {
        let exposureID = await MainActor.run { exposure.id }
        processedExposureIDs.append(exposureID)
        await MainActor.run {
            exposure.sync_state = .synced
            exposure.last_error = nil
            exposure.updated_at = .now
        }
        try await exposureMirrorStore.saveExposure(exposure)
    }
}

private func makeRunnerExposure(
    id: UUID,
    rollID: UUID,
    exposureNumber: Int,
    syncState: V2Domain.ExposureSyncState
) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
        exposure_number: exposureNumber,
        render_seed: "seed-\(exposureNumber)",
        sync_state: syncState,
        updated_at: .now
    )
}
