import Combine
import Foundation
import UIKit

@MainActor
final class V2SharedRevealGalleryViewModel: ObservableObject {
    struct GalleryItem: Identifiable {
        let id: UUID
        let exposureNumber: Int
        let image: UIImage?
        let renderSeed: String
        let syncState: V2Domain.ExposureSyncState
        let localOriginalPath: String?
        let localOriginalAvailable: Bool
        let cloudStoragePath: String?
        let renderingSource: V2GalleryRenderingSource
        let renderDurationMilliseconds: Double?
        let renderError: String?
    }

    struct ParticipantSection: Identifiable {
        let id: UUID
        let participantID: UUID
        let displayName: String
        let isCurrentUser: Bool
        let isCreator: Bool
        let status: V2Domain.ParticipantStatus
        let items: [GalleryItem]
    }

    @Published private(set) var state: V2PersonalRevealGalleryState = .idle
    @Published private(set) var roll: LocalRoll?
    @Published private(set) var sections: [ParticipantSection] = []
    @Published private(set) var isLoading = false

    private let rollID: UUID
    private let authRepository: any AuthRepository
    private let rollRepository: any RollRepository
    private let participantRepository: any ParticipantRepository
    private let exposureRepository: any ExposureRepository
    private let exposureMirrorStore: any ExposureMirrorStore
    private let imageProvider: any V2LocalImageProviding
    private let storageRepository: any ExposureAssetStorageRepository
    private let renderer: any V2ExposureImageRendering
    private let diagnosticsEnabled: Bool

    init(
        rollID: UUID,
        authRepository: any AuthRepository,
        rollRepository: any RollRepository,
        participantRepository: any ParticipantRepository,
        exposureRepository: any ExposureRepository,
        exposureMirrorStore: any ExposureMirrorStore,
        imageProvider: (any V2LocalImageProviding)? = nil,
        storageRepository: any ExposureAssetStorageRepository,
        renderer: (any V2ExposureImageRendering)? = nil,
        diagnosticsEnabled: Bool? = nil
    ) {
        self.rollID = rollID
        self.authRepository = authRepository
        self.rollRepository = rollRepository
        self.participantRepository = participantRepository
        self.exposureRepository = exposureRepository
        self.exposureMirrorStore = exposureMirrorStore
        self.imageProvider = imageProvider ?? PhotoStorageService()
        self.storageRepository = storageRepository
        self.renderer = renderer ?? PhotoRenderService()
        self.diagnosticsEnabled = diagnosticsEnabled ?? AppConfig.V2.isExposureDiagnosticsEnabled
    }

    var title: String {
        roll?.title ?? "Shared Gallery"
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
        sections.flatMap(\.items).contains { $0.renderError != nil }
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

        let session = try await authRepository.currentSession()
        let participants = try await participantRepository.fetchParticipants(forRollID: rollID)
        let cloudExposures = try await exposureRepository.fetchExposures(forRollID: rollID)
        let mirroredExposures = try await exposureMirrorStore.mirrorCloudExposures(cloudExposures, forRollID: rollID)

        roll = fetchedRoll
        sections = try await buildSections(
            from: mirroredExposures,
            participants: participants,
            roll: fetchedRoll,
            currentUserID: session?.userID
        )
    }

    private func buildSections(
        from exposures: [LocalExposure],
        participants: [LocalParticipant],
        roll: LocalRoll,
        currentUserID: UUID?
    ) async throws -> [ParticipantSection] {
        let groupedExposures = Dictionary(grouping: exposures, by: \.participant_id)

        var builtSections: [ParticipantSection] = []
        for participant in participants {
            let items = try await buildItems(
                from: groupedExposures[participant.id] ?? [],
                roll: roll
            )

            builtSections.append(
                ParticipantSection(
                    id: participant.id,
                    participantID: participant.id,
                    displayName: participant.display_name ?? "Participant",
                    isCurrentUser: participant.user_id == currentUserID,
                    isCreator: participant.user_id == roll.creator_id,
                    status: participant.status,
                    items: items.sorted(by: { $0.exposureNumber < $1.exposureNumber })
                )
            )
        }

        return builtSections
    }

    private func buildItems(
        from exposures: [LocalExposure],
        roll: LocalRoll
    ) async throws -> [GalleryItem] {
        let filmStock = FilmStock(rawValue: roll.film_stock_id) ?? .kodakGold200
        var items: [GalleryItem] = []

        for exposure in exposures.sorted(by: { $0.exposure_number < $1.exposure_number }) {
            items.append(try await buildItem(for: exposure, filmStock: filmStock))
        }

        return items
    }

    private func buildItem(
        for exposure: LocalExposure,
        filmStock: FilmStock
    ) async throws -> GalleryItem {
        if let localOriginalPath = exposure.local_original_path,
           let originalImage = imageProvider.loadImage(at: localOriginalPath) {
            return renderItem(
                exposure: exposure,
                sourceImage: originalImage,
                filmStock: filmStock,
                localOriginalPath: localOriginalPath,
                localOriginalAvailable: true,
                cloudStoragePath: exposure.cloud_storage_path,
                renderingSource: .local
            )
        }

        if let cloudStoragePath = exposure.cloud_storage_path,
           let downloadedImage = try await downloadCloudImage(at: cloudStoragePath) {
            return renderItem(
                exposure: exposure,
                sourceImage: downloadedImage,
                filmStock: filmStock,
                localOriginalPath: exposure.local_original_path,
                localOriginalAvailable: false,
                cloudStoragePath: cloudStoragePath,
                renderingSource: .cloud
            )
        }

        return GalleryItem(
            id: exposure.id,
            exposureNumber: exposure.exposure_number,
            image: nil,
            renderSeed: exposure.render_seed,
            syncState: exposure.sync_state,
            localOriginalPath: exposure.local_original_path,
            localOriginalAvailable: false,
            cloudStoragePath: exposure.cloud_storage_path,
            renderingSource: .unavailable,
            renderDurationMilliseconds: nil,
            renderError: "No local original or cloud image is currently available."
        )
    }

    private func renderItem(
        exposure: LocalExposure,
        sourceImage: UIImage,
        filmStock: FilmStock,
        localOriginalPath: String?,
        localOriginalAvailable: Bool,
        cloudStoragePath: String?,
        renderingSource: V2GalleryRenderingSource
    ) -> GalleryItem {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let renderedImage = try renderer.renderImage(
                for: sourceImage,
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
                localOriginalAvailable: localOriginalAvailable,
                cloudStoragePath: cloudStoragePath,
                renderingSource: renderingSource,
                renderDurationMilliseconds: (CFAbsoluteTimeGetCurrent() - startTime) * 1000,
                renderError: nil
            )
        } catch {
            return GalleryItem(
                id: exposure.id,
                exposureNumber: exposure.exposure_number,
                image: sourceImage,
                renderSeed: exposure.render_seed,
                syncState: exposure.sync_state,
                localOriginalPath: localOriginalPath,
                localOriginalAvailable: localOriginalAvailable,
                cloudStoragePath: cloudStoragePath,
                renderingSource: renderingSource,
                renderDurationMilliseconds: (CFAbsoluteTimeGetCurrent() - startTime) * 1000,
                renderError: error.localizedDescription
            )
        }
    }

    private func downloadCloudImage(at storagePath: String) async throws -> UIImage? {
        let data = try await storageRepository.downloadJPEG(from: storagePath)
        return UIImage(data: data)
    }
}
