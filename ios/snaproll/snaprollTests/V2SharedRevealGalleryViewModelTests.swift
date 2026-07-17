import Foundation
import Testing
import UIKit
@testable import snaproll

@MainActor
struct V2SharedRevealGalleryViewModelTests {
    @Test
    func sharedGalleryGroupsByParticipantAndPreservesExposureOrdering() async {
        let rollID = UUID(uuidString: "81818181-0000-0000-0000-000000000001")!
        let creatorUserID = UUID(uuidString: "81818181-0000-0000-0000-0000000000A1")!
        let creatorParticipantID = UUID(uuidString: "81818181-0000-0000-0000-0000000000B2")!
        let otherParticipantID = UUID(uuidString: "81818181-0000-0000-0000-0000000000C3")!
        let participants = [
            makeSharedGalleryParticipant(id: creatorParticipantID, rollID: rollID, userID: creatorUserID, name: "Creator", status: .finished),
            makeSharedGalleryParticipant(id: otherParticipantID, rollID: rollID, userID: UUID(), name: "Participant B", status: .finished)
        ]
        let exposures = [
            makeSharedGalleryExposure(id: UUID(), rollID: rollID, participantID: creatorParticipantID, exposureNumber: 2, renderSeed: "c-2", localPath: "creator-2.png"),
            makeSharedGalleryExposure(id: UUID(), rollID: rollID, participantID: creatorParticipantID, exposureNumber: 1, renderSeed: "c-1", localPath: "creator-1.png"),
            makeSharedGalleryExposure(id: UUID(), rollID: rollID, participantID: otherParticipantID, exposureNumber: 2, renderSeed: "o-2", localPath: "other-2.png"),
            makeSharedGalleryExposure(id: UUID(), rollID: rollID, participantID: otherParticipantID, exposureNumber: 1, renderSeed: "o-1", localPath: "other-1.png")
        ]
        let imageProvider = SharedGalleryImageProvider(imagesByPath: [
            "creator-1.png": sampleGalleryImage(),
            "creator-2.png": sampleGalleryImage(),
            "other-1.png": sampleGalleryImage(),
            "other-2.png": sampleGalleryImage()
        ])
        let viewModel = V2SharedRevealGalleryViewModel(
            rollID: rollID,
            authRepository: SharedGalleryAuthRepository(session: AuthSession(userID: creatorUserID, displayName: "Creator")),
            rollRepository: SharedGalleryRollRepository(roll: makeSharedGalleryRoll(id: rollID, creatorID: creatorUserID)),
            participantRepository: SharedGalleryParticipantRepository(participants: participants),
            exposureRepository: SharedGalleryExposureRepository(exposures: exposures),
            exposureMirrorStore: SharedGalleryMirrorStore(),
            imageProvider: imageProvider,
            storageRepository: SharedGalleryStorageRepository(),
            renderer: SharedGalleryRenderer()
        )

        await viewModel.load()

        #expect(viewModel.sections.count == 2)
        #expect(viewModel.sections[0].displayName == "Creator")
        #expect(viewModel.sections[0].isCurrentUser)
        #expect(viewModel.sections[0].items.map(\.exposureNumber) == [1, 2])
        #expect(viewModel.sections[1].displayName == "Participant B")
        #expect(viewModel.sections[1].items.map(\.exposureNumber) == [1, 2])
    }

    @Test
    func sharedGalleryPrefersLocalOriginalBeforeCloudDownload() async {
        let rollID = UUID(uuidString: "82828282-0000-0000-0000-000000000001")!
        let creatorUserID = UUID(uuidString: "82828282-0000-0000-0000-0000000000A1")!
        let participantID = UUID(uuidString: "82828282-0000-0000-0000-0000000000B2")!
        let localPath = "local.png"
        let cloudPath = "rolls/\(rollID.uuidString.lowercased())/participants/\(participantID.uuidString.lowercased())/001.jpg"
        let exposure = makeSharedGalleryExposure(
            id: UUID(),
            rollID: rollID,
            participantID: participantID,
            exposureNumber: 1,
            renderSeed: "seed-1",
            localPath: localPath,
            cloudStoragePath: cloudPath
        )
        let storageRepository = SharedGalleryStorageRepository(downloadsByPath: [cloudPath: sampleGalleryPNGData()])
        let viewModel = V2SharedRevealGalleryViewModel(
            rollID: rollID,
            authRepository: SharedGalleryAuthRepository(session: AuthSession(userID: creatorUserID, displayName: "Creator")),
            rollRepository: SharedGalleryRollRepository(roll: makeSharedGalleryRoll(id: rollID, creatorID: creatorUserID)),
            participantRepository: SharedGalleryParticipantRepository(
                participants: [makeSharedGalleryParticipant(id: participantID, rollID: rollID, userID: creatorUserID, name: "Creator", status: .finished)]
            ),
            exposureRepository: SharedGalleryExposureRepository(exposures: [exposure]),
            exposureMirrorStore: SharedGalleryMirrorStore(),
            imageProvider: SharedGalleryImageProvider(imagesByPath: [localPath: sampleGalleryImage()]),
            storageRepository: storageRepository,
            renderer: SharedGalleryRenderer()
        )

        await viewModel.load()

        #expect(viewModel.sections.first?.items.first?.renderingSource == .local)
        #expect(await storageRepository.downloadedPaths.isEmpty)
    }

    @Test
    func sharedGalleryFallsBackToCloudAndReusesRenderer() async {
        let rollID = UUID(uuidString: "83838383-0000-0000-0000-000000000001")!
        let creatorUserID = UUID(uuidString: "83838383-0000-0000-0000-0000000000A1")!
        let participantID = UUID(uuidString: "83838383-0000-0000-0000-0000000000B2")!
        let cloudPath = "rolls/\(rollID.uuidString.lowercased())/participants/\(participantID.uuidString.lowercased())/001.jpg"
        let renderer = SharedGalleryRenderer()
        let storageRepository = SharedGalleryStorageRepository(downloadsByPath: [cloudPath: sampleGalleryPNGData()])
        let exposure = makeSharedGalleryExposure(
            id: UUID(),
            rollID: rollID,
            participantID: participantID,
            exposureNumber: 1,
            renderSeed: "seed-1",
            localPath: nil,
            cloudStoragePath: cloudPath
        )
        let viewModel = V2SharedRevealGalleryViewModel(
            rollID: rollID,
            authRepository: SharedGalleryAuthRepository(session: AuthSession(userID: creatorUserID, displayName: "Creator")),
            rollRepository: SharedGalleryRollRepository(roll: makeSharedGalleryRoll(id: rollID, creatorID: creatorUserID)),
            participantRepository: SharedGalleryParticipantRepository(
                participants: [makeSharedGalleryParticipant(id: participantID, rollID: rollID, userID: creatorUserID, name: "Creator", status: .finished)]
            ),
            exposureRepository: SharedGalleryExposureRepository(exposures: [exposure]),
            exposureMirrorStore: SharedGalleryMirrorStore(),
            imageProvider: SharedGalleryImageProvider(imagesByPath: [:]),
            storageRepository: storageRepository,
            renderer: renderer
        )

        await viewModel.load()

        #expect(viewModel.sections.first?.items.first?.renderingSource == .cloud)
        #expect(await storageRepository.downloadedPaths == [cloudPath])
        #expect(await renderer.calls.count == 1)
    }

    @Test
    func sharedGalleryItemsExposeRenderedImageDimensions() async {
        let rollID = UUID(uuidString: "84848484-0000-0000-0000-000000000001")!
        let creatorUserID = UUID(uuidString: "84848484-0000-0000-0000-0000000000A1")!
        let participantID = UUID(uuidString: "84848484-0000-0000-0000-0000000000B2")!
        let participants = [
            makeSharedGalleryParticipant(id: participantID, rollID: rollID, userID: creatorUserID, name: "Creator", status: .finished)
        ]
        let exposures = [
            makeSharedGalleryExposure(id: UUID(), rollID: rollID, participantID: participantID, exposureNumber: 1, renderSeed: "portrait", localPath: "portrait.png"),
            makeSharedGalleryExposure(id: UUID(), rollID: rollID, participantID: participantID, exposureNumber: 2, renderSeed: "landscape", localPath: "landscape.png")
        ]
        let viewModel = V2SharedRevealGalleryViewModel(
            rollID: rollID,
            authRepository: SharedGalleryAuthRepository(session: AuthSession(userID: creatorUserID, displayName: "Creator")),
            rollRepository: SharedGalleryRollRepository(roll: makeSharedGalleryRoll(id: rollID, creatorID: creatorUserID)),
            participantRepository: SharedGalleryParticipantRepository(participants: participants),
            exposureRepository: SharedGalleryExposureRepository(exposures: exposures),
            exposureMirrorStore: SharedGalleryMirrorStore(),
            imageProvider: SharedGalleryImageProvider(imagesByPath: [
                "portrait.png": sampleGalleryImage(size: CGSize(width: 90, height: 160)),
                "landscape.png": sampleGalleryImage(size: CGSize(width: 160, height: 90))
            ]),
            storageRepository: SharedGalleryStorageRepository(),
            renderer: SharedGalleryRenderer()
        )

        await viewModel.load()

        let items = viewModel.sections.first?.items ?? []
        #expect(items[0].pixelHeight > items[0].pixelWidth)
        #expect(items[1].pixelWidth > items[1].pixelHeight)
    }
}

private actor SharedGalleryAuthRepository: AuthRepository {
    private let session: AuthSession?

    init(session: AuthSession?) {
        self.session = session
    }

    func currentSession() async throws -> AuthSession? { session }
    func currentUserID() async throws -> UUID? { session?.userID }
    func signOut() async throws {}
}

private actor SharedGalleryRollRepository: RollRepository {
    private let snapshot: SharedGalleryRollSnapshot

    init(roll: LocalRoll) {
        self.snapshot = SharedGalleryRollSnapshot(roll)
    }

    func fetchRoll(id: UUID) async throws -> LocalRoll? {
        guard snapshot.id == id else { return nil }
        let snapshot = snapshot
        return await MainActor.run { snapshot.makeLocalRoll() }
    }

    func fetchRolls() async throws -> [LocalRoll] { [] }
    func fetchAllRolls() async throws -> [LocalRoll] { [] }
    func startRoll(id: UUID) async throws {}
    func revealRoll(id: UUID) async throws {}
    func createRoll(title: String, type: V2Domain.RollType, filmStockID: String, exposuresPerParticipant: Int, participantCap: Int) async throws -> CreateRollResult {
        CreateRollResult(rollID: UUID(), inviteToken: nil)
    }
    func saveRoll(_ roll: LocalRoll) async throws {}
    func deleteRoll(id: UUID) async throws {}
}

private actor SharedGalleryParticipantRepository: ParticipantRepository {
    private let snapshots: [SharedGalleryParticipantSnapshot]

    init(participants: [LocalParticipant]) {
        self.snapshots = participants.map(SharedGalleryParticipantSnapshot.init)
    }

    func fetchParticipants(forRollID rollID: UUID) async throws -> [LocalParticipant] {
        let snapshots = snapshots.filter { $0.rollID == rollID }
        return await MainActor.run { snapshots.map { $0.makeLocalParticipant() } }
    }

    func fetchParticipant(id: UUID) async throws -> LocalParticipant? { nil }
    func joinRoll(inviteToken: String) async throws -> JoinRollResult { JoinRollResult(rollID: UUID(), participantID: UUID()) }
    func leaveRoll(rollID: UUID) async throws {}
    func saveParticipant(_ participant: LocalParticipant) async throws {}
    func deleteParticipant(id: UUID) async throws {}
}

private actor SharedGalleryExposureRepository: ExposureRepository {
    private let snapshots: [SharedGalleryExposureSnapshot]

    init(exposures: [LocalExposure]) {
        self.snapshots = exposures.map(SharedGalleryExposureSnapshot.init)
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        let snapshots = snapshots.filter { $0.rollID == rollID }.sorted { $0.exposureNumber < $1.exposureNumber }
        return await MainActor.run { snapshots.map { $0.makeLocalExposure() } }
    }

    func fetchExposures(forParticipantID participantID: UUID) async throws -> [LocalExposure] { [] }
    func fetchExposure(id: UUID) async throws -> LocalExposure? { nil }
    func completeExposure(id: UUID, storagePath: String) async throws -> CompleteExposureResult {
        CompleteExposureResult(participantFinished: false, rollReadyToReveal: false)
    }
    func saveExposure(_ exposure: LocalExposure) async throws {}
    func saveExposures(_ exposures: [LocalExposure]) async throws {}
}

@MainActor
private final class SharedGalleryMirrorStore: ExposureMirrorStore {
    private var exposuresByRollID: [UUID: [LocalExposure]] = [:]

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] ?? []
    }

    func mirrorCloudExposures(_ exposures: [LocalExposure], forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] = exposures.sorted { $0.exposure_number < $1.exposure_number }
        return exposuresByRollID[rollID] ?? []
    }

    func saveExposure(_ exposure: LocalExposure) async throws {}
}

private final class SharedGalleryImageProvider: V2LocalImageProviding {
    private let imagesByPath: [String: UIImage]

    init(imagesByPath: [String: UIImage]) {
        self.imagesByPath = imagesByPath
    }

    func loadImage(at localPath: String) -> UIImage? {
        imagesByPath[localPath]
    }
}

private actor SharedGalleryStorageRepository: ExposureAssetStorageRepository {
    private let downloadsByPath: [String: Data]
    private(set) var downloadedPaths: [String] = []

    init(downloadsByPath: [String: Data] = [:]) {
        self.downloadsByPath = downloadsByPath
    }

    func uploadJPEG(data: Data, to storagePath: String) async throws {}

    func downloadJPEG(from storagePath: String) async throws -> Data {
        downloadedPaths.append(storagePath)
        return downloadsByPath[storagePath] ?? sampleGalleryPNGData()
    }
}

@MainActor
private final class SharedGalleryRenderer: V2ExposureImageRendering {
    struct Call: Equatable {
        let filmStock: FilmStock
        let renderSeed: String
        let cacheKey: String
    }

    private(set) var calls: [Call] = []

    func renderImage(for image: UIImage, filmStock: FilmStock, renderSeed: String, cacheKey: String) throws -> UIImage {
        calls.append(Call(filmStock: filmStock, renderSeed: renderSeed, cacheKey: cacheKey))
        return image
    }
}

private struct SharedGalleryRollSnapshot {
    let id: UUID
    let title: String
    let type: V2Domain.RollType
    let status: V2Domain.RollStatus
    let filmStockID: String
    let exposuresPerParticipant: Int
    let creatorID: UUID
    let createdAt: Date

    init(_ roll: LocalRoll) {
        self.id = roll.id
        self.title = roll.title
        self.type = roll.type
        self.status = roll.status
        self.filmStockID = roll.film_stock_id
        self.exposuresPerParticipant = roll.exposures_per_participant
        self.creatorID = roll.creator_id
        self.createdAt = roll.created_at
    }

    func makeLocalRoll() -> LocalRoll {
        LocalRoll(
            id: id,
            title: title,
            type: type,
            status: status,
            film_stock_id: filmStockID,
            exposures_per_participant: exposuresPerParticipant,
            creator_id: creatorID,
            created_at: createdAt
        )
    }
}

private struct SharedGalleryParticipantSnapshot {
    let id: UUID
    let rollID: UUID
    let userID: UUID
    let displayName: String?
    let status: V2Domain.ParticipantStatus
    let joinedAt: Date

    init(_ participant: LocalParticipant) {
        self.id = participant.id
        self.rollID = participant.roll_id
        self.userID = participant.user_id
        self.displayName = participant.display_name
        self.status = participant.status
        self.joinedAt = participant.joined_at
    }

    func makeLocalParticipant() -> LocalParticipant {
        LocalParticipant(
            id: id,
            roll_id: rollID,
            user_id: userID,
            display_name: displayName,
            status: status,
            joined_at: joinedAt
        )
    }
}

private struct SharedGalleryExposureSnapshot {
    let id: UUID
    let rollID: UUID
    let participantID: UUID
    let exposureNumber: Int
    let renderSeed: String
    let localOriginalPath: String?
    let cloudStoragePath: String?
    let syncState: V2Domain.ExposureSyncState
    let updatedAt: Date

    init(_ exposure: LocalExposure) {
        self.id = exposure.id
        self.rollID = exposure.roll_id
        self.participantID = exposure.participant_id
        self.exposureNumber = exposure.exposure_number
        self.renderSeed = exposure.render_seed
        self.localOriginalPath = exposure.local_original_path
        self.cloudStoragePath = exposure.cloud_storage_path
        self.syncState = exposure.sync_state
        self.updatedAt = exposure.updated_at
    }

    func makeLocalExposure() -> LocalExposure {
        LocalExposure(
            id: id,
            roll_id: rollID,
            participant_id: participantID,
            exposure_number: exposureNumber,
            render_seed: renderSeed,
            local_original_path: localOriginalPath,
            cloud_storage_path: cloudStoragePath,
            sync_state: syncState,
            updated_at: updatedAt
        )
    }
}

private func makeSharedGalleryRoll(id: UUID, creatorID: UUID) -> LocalRoll {
    LocalRoll(
        id: id,
        title: "Shared Reveal",
        type: .shared,
        status: .revealed,
        film_stock_id: FilmStock.kodakGold200.rawValue,
        exposures_per_participant: 12,
        creator_id: creatorID,
        created_at: .now
    )
}

private func makeSharedGalleryParticipant(
    id: UUID,
    rollID: UUID,
    userID: UUID,
    name: String,
    status: V2Domain.ParticipantStatus
) -> LocalParticipant {
    LocalParticipant(
        id: id,
        roll_id: rollID,
        user_id: userID,
        display_name: name,
        status: status,
        joined_at: .now
    )
}

private func makeSharedGalleryExposure(
    id: UUID,
    rollID: UUID,
    participantID: UUID,
    exposureNumber: Int,
    renderSeed: String,
    localPath: String?,
    cloudStoragePath: String? = nil
) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: participantID,
        exposure_number: exposureNumber,
        render_seed: renderSeed,
        local_original_path: localPath,
        cloud_storage_path: cloudStoragePath,
        sync_state: .synced,
        updated_at: .now
    )
}

private func sampleGalleryImage(size: CGSize = CGSize(width: 24, height: 24)) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

private func sampleGalleryPNGData() -> Data {
    sampleGalleryImage().pngData()!
}
