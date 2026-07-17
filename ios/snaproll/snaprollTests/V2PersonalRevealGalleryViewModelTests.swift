import Foundation
import Testing
import UIKit
@testable import snaproll

@MainActor
struct V2PersonalRevealGalleryViewModelTests {
    @Test
    func galleryPreservesExposureNumberOrdering() async {
        let rollID = UUID(uuidString: "77777777-0000-0000-0000-000000000001")!
        let roll = makeGalleryRoll(id: rollID)
        let second = makeGalleryExposure(
            id: UUID(uuidString: "77777777-0000-0000-0000-000000000102")!,
            rollID: rollID,
            exposureNumber: 2,
            renderSeed: "seed-2"
        )
        second.local_original_path = "second.jpg"
        let first = makeGalleryExposure(
            id: UUID(uuidString: "77777777-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            renderSeed: "seed-1"
        )
        first.local_original_path = "first.jpg"

        let viewModel = V2PersonalRevealGalleryViewModel(
            rollID: rollID,
            rollRepository: FakeGalleryRollRepository(roll: roll),
            exposureRepository: FakeGalleryExposureRepository(exposures: [second, first]),
            exposureMirrorStore: GalleryMirrorStore(),
            imageProvider: FakeGalleryImageProvider(imagesByPath: [
                "first.jpg": makeImage(size: CGSize(width: 100, height: 120), color: .red),
                "second.jpg": makeImage(size: CGSize(width: 120, height: 100), color: .blue)
            ]),
            renderer: FakeGalleryRenderer()
        )

        await viewModel.load()

        #expect(viewModel.items.map(\.exposureNumber) == [1, 2])
    }

    @Test
    func rendererReceivesOriginalImageFilmStockAndRenderSeed() async {
        let rollID = UUID(uuidString: "88888888-0000-0000-0000-000000000001")!
        let roll = makeGalleryRoll(id: rollID, filmStockID: FilmStock.fujifilmSuperia400.rawValue)
        let exposure = makeGalleryExposure(
            id: UUID(uuidString: "88888888-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            renderSeed: "gallery-seed"
        )
        exposure.local_original_path = "original.jpg"

        let renderer = FakeGalleryRenderer()
        let viewModel = V2PersonalRevealGalleryViewModel(
            rollID: rollID,
            rollRepository: FakeGalleryRollRepository(roll: roll),
            exposureRepository: FakeGalleryExposureRepository(exposures: [exposure]),
            exposureMirrorStore: GalleryMirrorStore(),
            imageProvider: FakeGalleryImageProvider(imagesByPath: [
                "original.jpg": makeImage(size: CGSize(width: 321, height: 123), color: .green)
            ]),
            renderer: renderer
        )

        await viewModel.load()

        let call = try? #require(renderer.calls.first)
        #expect(call?.filmStock == .fujifilmSuperia400)
        #expect(call?.renderSeed == "gallery-seed")
        #expect(call?.inputSize == CGSize(width: 321, height: 123))
    }

    @Test
    func localOriginalIsPreferredOverUploadJPEG() async {
        let rollID = UUID(uuidString: "99999999-0000-0000-0000-000000000001")!
        let roll = makeGalleryRoll(id: rollID)
        let exposure = makeGalleryExposure(
            id: UUID(uuidString: "99999999-0000-0000-0000-000000000101")!,
            rollID: rollID,
            exposureNumber: 1,
            renderSeed: "local-first"
        )
        exposure.local_original_path = "original.jpg"
        exposure.upload_jpeg_path = "upload.jpg"

        let imageProvider = FakeGalleryImageProvider(imagesByPath: [
            "original.jpg": makeImage(size: CGSize(width: 240, height: 180), color: .yellow),
            "upload.jpg": makeImage(size: CGSize(width: 10, height: 10), color: .purple)
        ])
        let viewModel = V2PersonalRevealGalleryViewModel(
            rollID: rollID,
            rollRepository: FakeGalleryRollRepository(roll: roll),
            exposureRepository: FakeGalleryExposureRepository(exposures: [exposure]),
            exposureMirrorStore: GalleryMirrorStore(),
            imageProvider: imageProvider,
            renderer: FakeGalleryRenderer()
        )

        await viewModel.load()

        #expect(imageProvider.accessedPaths == ["original.jpg"])
        #expect(viewModel.items.first?.renderingSource == .local)
    }

    @Test
    func galleryItemsExposeRenderedImageDimensions() async {
        let rollID = UUID(uuidString: "BBBBBBBB-2222-2222-2222-222222222222")!
        let roll = makeGalleryRoll(id: rollID)
        let portrait = makeGalleryExposure(
            id: UUID(uuidString: "BBBBBBBB-2222-2222-2222-222222222201")!,
            rollID: rollID,
            exposureNumber: 1,
            renderSeed: "portrait"
        )
        portrait.local_original_path = "portrait.jpg"
        let landscape = makeGalleryExposure(
            id: UUID(uuidString: "BBBBBBBB-2222-2222-2222-222222222202")!,
            rollID: rollID,
            exposureNumber: 2,
            renderSeed: "landscape"
        )
        landscape.local_original_path = "landscape.jpg"

        let viewModel = V2PersonalRevealGalleryViewModel(
            rollID: rollID,
            rollRepository: FakeGalleryRollRepository(roll: roll),
            exposureRepository: FakeGalleryExposureRepository(exposures: [portrait, landscape]),
            exposureMirrorStore: GalleryMirrorStore(),
            imageProvider: FakeGalleryImageProvider(imagesByPath: [
                "portrait.jpg": makeImage(size: CGSize(width: 90, height: 160), color: .red),
                "landscape.jpg": makeImage(size: CGSize(width: 160, height: 90), color: .blue)
            ]),
            renderer: FakeGalleryRenderer()
        )

        await viewModel.load()

        #expect(viewModel.items[0].pixelHeight > viewModel.items[0].pixelWidth)
        #expect(viewModel.items[1].pixelWidth > viewModel.items[1].pixelHeight)
    }

    @Test
    func renderFailureRemainsRecoverable() async {
        let rollID = UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111111")!
        let roll = makeGalleryRoll(id: rollID)
        let exposure = makeGalleryExposure(
            id: UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111101")!,
            rollID: rollID,
            exposureNumber: 1,
            renderSeed: "retry-seed"
        )
        exposure.local_original_path = "retry.jpg"

        let renderer = FakeGalleryRenderer(shouldFail: true)
        let viewModel = V2PersonalRevealGalleryViewModel(
            rollID: rollID,
            rollRepository: FakeGalleryRollRepository(roll: roll),
            exposureRepository: FakeGalleryExposureRepository(exposures: [exposure]),
            exposureMirrorStore: GalleryMirrorStore(),
            imageProvider: FakeGalleryImageProvider(imagesByPath: [
                "retry.jpg": makeImage(size: CGSize(width: 200, height: 300), color: .orange)
            ]),
            renderer: renderer,
            diagnosticsEnabled: true
        )

        await viewModel.load()
        #expect(viewModel.items.first?.renderError != nil)
        #expect(viewModel.items.first?.image != nil)

        renderer.shouldFail = false
        await viewModel.retryRendering()

        #expect(viewModel.items.first?.renderError == nil)
        #expect(viewModel.hasRecoverableRenderFailures == false)
    }
}

private actor FakeGalleryRollRepository: RollRepository {
    private let roll: LocalRoll

    init(roll: LocalRoll) {
        self.roll = roll
    }

    func fetchRoll(id: UUID) async throws -> LocalRoll? { roll }
    func fetchRolls() async throws -> [LocalRoll] { [roll] }
    func fetchAllRolls() async throws -> [LocalRoll] { [roll] }
    func startRoll(id: UUID) async throws {}
    func revealRoll(id: UUID) async throws {}
    func createRoll(
        title: String,
        type: V2Domain.RollType,
        filmStockID: String,
        exposuresPerParticipant: Int,
        participantCap: Int
    ) async throws -> CreateRollResult {
        CreateRollResult(rollID: roll.id, inviteToken: nil)
    }
    func saveRoll(_ roll: LocalRoll) async throws {}
    func deleteRoll(id: UUID) async throws {}
}

private actor FakeGalleryExposureRepository: ExposureRepository {
    private let exposures: [LocalExposure]

    init(exposures: [LocalExposure]) {
        self.exposures = exposures
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] { exposures }
    func fetchExposures(forParticipantID participantID: UUID) async throws -> [LocalExposure] { exposures }
    func fetchExposure(id: UUID) async throws -> LocalExposure? { exposures.first(where: { $0.id == id }) }
    func completeExposure(id: UUID, storagePath: String) async throws -> CompleteExposureResult {
        CompleteExposureResult(participantFinished: false, rollReadyToReveal: false)
    }
    func saveExposure(_ exposure: LocalExposure) async throws {}
    func saveExposures(_ exposures: [LocalExposure]) async throws {}
}

@MainActor
private final class GalleryMirrorStore: ExposureMirrorStore {
    private var exposuresByRollID: [UUID: [LocalExposure]] = [:]

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] ?? []
    }

    func mirrorCloudExposures(_ exposures: [LocalExposure], forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] = exposures.sorted { $0.exposure_number < $1.exposure_number }
        return exposuresByRollID[rollID] ?? []
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

@MainActor
private final class FakeGalleryImageProvider: V2LocalImageProviding {
    private let imagesByPath: [String: UIImage]
    private(set) var accessedPaths: [String] = []

    init(imagesByPath: [String: UIImage]) {
        self.imagesByPath = imagesByPath
    }

    func loadImage(at localPath: String) -> UIImage? {
        accessedPaths.append(localPath)
        return imagesByPath[localPath]
    }
}

private final class FakeGalleryRenderer: V2ExposureImageRendering, @unchecked Sendable {
    struct Call: Equatable {
        let filmStock: FilmStock
        let renderSeed: String
        let inputSize: CGSize
    }

    private(set) var calls: [Call] = []
    var shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func renderImage(
        for image: UIImage,
        filmStock: FilmStock,
        renderSeed: String,
        cacheKey: String
    ) throws -> UIImage {
        calls.append(
            Call(
                filmStock: filmStock,
                renderSeed: renderSeed,
                inputSize: image.size
            )
        )

        if shouldFail {
            throw NSError(domain: "GalleryRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated render failure"])
        }

        return image
    }
}

private func makeGalleryRoll(id: UUID, filmStockID: String = FilmStock.kodakGold200.rawValue) -> LocalRoll {
    LocalRoll(
        id: id,
        title: "Reveal Roll",
        type: .personal,
        status: .revealed,
        film_stock_id: filmStockID,
        exposures_per_participant: 12,
        creator_id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
        created_at: .now,
        revealed_at: .now
    )
}

private func makeGalleryExposure(
    id: UUID,
    rollID: UUID,
    exposureNumber: Int,
    renderSeed: String
) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
        exposure_number: exposureNumber,
        render_seed: renderSeed,
        sync_state: .synced,
        updated_at: .now
    )
}

@MainActor
private func makeImage(size: CGSize, color: UIColor) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}
