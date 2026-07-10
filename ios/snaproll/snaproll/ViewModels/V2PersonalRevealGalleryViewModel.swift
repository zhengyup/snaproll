import Combine
import Foundation
import UIKit

protocol V2ExposureImageRendering {
    func renderImage(
        for image: UIImage,
        filmStock: FilmStock,
        renderSeed: String,
        cacheKey: String
    ) throws -> UIImage
}

protocol V2LocalImageProviding {
    func loadImage(at localPath: String) -> UIImage?
}

extension PhotoRenderService: V2ExposureImageRendering {
    func renderImage(
        for image: UIImage,
        filmStock: FilmStock,
        renderSeed: String,
        cacheKey: String
    ) throws -> UIImage {
        renderedImage(
            for: image,
            filmStock: filmStock,
            cacheKey: "\(cacheKey)::\(renderSeed)"
        )
    }
}

extension PhotoStorageService: V2LocalImageProviding {}

enum V2PersonalRevealGalleryState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum V2GalleryRenderingSource: String, Equatable {
    case local = "LOCAL"
    case unavailable = "UNAVAILABLE"
}

@MainActor
final class V2PersonalRevealGalleryViewModel: ObservableObject {
    struct GalleryItem: Identifiable {
        let id: UUID
        let exposureNumber: Int
        let image: UIImage?
        let renderSeed: String
        let syncState: V2Domain.ExposureSyncState
        let localOriginalPath: String?
        let localOriginalAvailable: Bool
        let renderingSource: V2GalleryRenderingSource
        let renderDurationMilliseconds: Double?
        let renderError: String?
    }

    @Published private(set) var state: V2PersonalRevealGalleryState = .idle
    @Published private(set) var roll: LocalRoll?
    @Published private(set) var items: [GalleryItem] = []
    @Published private(set) var isLoading = false

    private let rollID: UUID
    private let rollRepository: any RollRepository
    private let exposureRepository: any ExposureRepository
    private let exposureMirrorStore: any ExposureMirrorStore
    private let imageProvider: any V2LocalImageProviding
    private let renderer: any V2ExposureImageRendering
    private let diagnosticsEnabled: Bool

    init(
        rollID: UUID,
        rollRepository: any RollRepository,
        exposureRepository: any ExposureRepository,
        exposureMirrorStore: any ExposureMirrorStore,
        imageProvider: (any V2LocalImageProviding)? = nil,
        renderer: (any V2ExposureImageRendering)? = nil,
        diagnosticsEnabled: Bool? = nil
    ) {
        self.rollID = rollID
        self.rollRepository = rollRepository
        self.exposureRepository = exposureRepository
        self.exposureMirrorStore = exposureMirrorStore
        self.imageProvider = imageProvider ?? PhotoStorageService()
        self.renderer = renderer ?? PhotoRenderService()
        self.diagnosticsEnabled = diagnosticsEnabled ?? AppConfig.V2.isExposureDiagnosticsEnabled
    }

    var title: String {
        roll?.title ?? "Gallery"
    }

    var filmLabel: String {
        guard let roll else {
            return "Unknown Film"
        }

        return FilmStock(rawValue: roll.film_stock_id)?.displayName ?? roll.film_stock_id
    }

    var shouldShowDiagnostics: Bool {
        diagnosticsEnabled
    }

    var hasRecoverableRenderFailures: Bool {
        items.contains { $0.renderError != nil }
    }

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        state = .loading
        defer { isLoading = false }

        do {
            try await reload()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retryRendering() async {
        await load()
    }

    private func reload() async throws {
        guard let fetchedRoll = try await rollRepository.fetchRoll(id: rollID) else {
            throw V2RepositoryError.notFound("The selected roll could not be found.")
        }

        let cloudExposures = try await exposureRepository.fetchExposures(forRollID: rollID)
        let mirroredExposures = try await exposureMirrorStore.mirrorCloudExposures(cloudExposures, forRollID: rollID)
            .sorted(by: { $0.exposure_number < $1.exposure_number })

        roll = fetchedRoll
        items = buildGalleryItems(from: mirroredExposures, roll: fetchedRoll)
    }

    private func buildGalleryItems(from exposures: [LocalExposure], roll: LocalRoll) -> [GalleryItem] {
        let filmStock = FilmStock(rawValue: roll.film_stock_id) ?? .kodakGold200

        return exposures.map { exposure in
            guard let localOriginalPath = exposure.local_original_path,
                  let originalImage = imageProvider.loadImage(at: localOriginalPath) else {
                return GalleryItem(
                    id: exposure.id,
                    exposureNumber: exposure.exposure_number,
                    image: nil,
                    renderSeed: exposure.render_seed,
                    syncState: exposure.sync_state,
                    localOriginalPath: exposure.local_original_path,
                    localOriginalAvailable: false,
                    renderingSource: .unavailable,
                    renderDurationMilliseconds: nil,
                    renderError: "Local original unavailable."
                )
            }

            let startTime = CFAbsoluteTimeGetCurrent()

            do {
                let renderedImage = try renderer.renderImage(
                    for: originalImage,
                    filmStock: filmStock,
                    renderSeed: exposure.render_seed,
                    cacheKey: exposure.id.uuidString.lowercased()
                )

                return GalleryItem(
                    id: exposure.id,
                    exposureNumber: exposure.exposure_number,
                    image: renderedImage,
                    renderSeed: exposure.render_seed,
                    syncState: exposure.sync_state,
                    localOriginalPath: localOriginalPath,
                    localOriginalAvailable: true,
                    renderingSource: .local,
                    renderDurationMilliseconds: (CFAbsoluteTimeGetCurrent() - startTime) * 1000,
                    renderError: nil
                )
            } catch {
                return GalleryItem(
                    id: exposure.id,
                    exposureNumber: exposure.exposure_number,
                    image: originalImage,
                    renderSeed: exposure.render_seed,
                    syncState: exposure.sync_state,
                    localOriginalPath: localOriginalPath,
                    localOriginalAvailable: true,
                    renderingSource: .local,
                    renderDurationMilliseconds: (CFAbsoluteTimeGetCurrent() - startTime) * 1000,
                    renderError: error.localizedDescription
                )
            }
        }
    }
}
