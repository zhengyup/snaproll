import Combine
import Foundation
import SwiftUI
import UIKit

struct RevealPhotoItem: Identifiable {
    let id: UUID
    let photo: Photo
    let image: UIImage?

    var aspectRatio: CGFloat {
        guard let image else {
            return 1
        }

        let size = image.size
        guard size.height > 0 else {
            return 1
        }

        return size.width / size.height
    }

    var isLandscape: Bool {
        aspectRatio > 1
    }
}

@MainActor
final class RevealViewModel: ObservableObject {
    @Published private(set) var roll: Roll
    @Published private(set) var photoItems: [RevealPhotoItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRevealing = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var isExporting = false
    @Published var feedbackNotice: UserFeedbackNotice?
    @Published var shareSheetPayload: ShareSheetPayload?

    private let localStorageService: LocalStorageService
    private let photoStorageService: PhotoStorageService
    private let photoRenderService: PhotoRenderService
    private let exportService: ExportService
    private let onRollUpdated: ((Roll) -> Void)?

    init(
        roll: Roll,
        localStorageService: LocalStorageService? = nil,
        photoStorageService: PhotoStorageService? = nil,
        photoRenderService: PhotoRenderService? = nil,
        exportService: ExportService? = nil,
        onRollUpdated: ((Roll) -> Void)? = nil
    ) {
        self.roll = roll
        self.localStorageService = localStorageService ?? LocalStorageService()
        self.photoStorageService = photoStorageService ?? PhotoStorageService()
        self.photoRenderService = photoRenderService ?? PhotoRenderService()
        self.exportService = exportService ?? ExportService(
            localStorageService: self.localStorageService,
            photoStorageService: self.photoStorageService,
            photoRenderService: self.photoRenderService
        )
        self.onRollUpdated = onRollUpdated
    }

    var showsGallery: Bool {
        roll.isRevealed
    }

    var hasPhotos: Bool {
        !photoItems.isEmpty
    }

    func handleAppear() {
        guard photoItems.isEmpty, !isLoading else {
            return
        }

        loadPhotos()
    }

    func revealRoll() {
        guard !roll.isRevealed, !isRevealing else {
            return
        }

        isRevealing = true
        statusMessage = nil

        Task {
            if photoItems.isEmpty {
                await loadPhotosIfNeeded()
            }

            do {
                let updatedRoll = try persistRevealedRoll()
                withAnimation(.easeInOut(duration: 0.35)) {
                    roll = updatedRoll
                }
                onRollUpdated?(updatedRoll)
            } catch {
                statusMessage = error.localizedDescription
            }

            isRevealing = false
        }
    }

    func exportRoll() {
        guard roll.isRevealed else {
            feedbackNotice = UserFeedbackNotice(
                title: "Export Unavailable",
                message: "Reveal this roll before exporting its memories."
            )
            return
        }

        isExporting = true

        Task {
            defer {
                isExporting = false
            }

            do {
                let summary = try await exportService.exportRenderedRollToLibrary(for: roll)
                feedbackNotice = UserFeedbackNotice(
                    title: "Export Finished",
                    message: "\(summary.exportedCount) exported\n\(summary.failedCount) failed"
                )
            } catch {
                feedbackNotice = UserFeedbackNotice(
                    title: "Export Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func shareRoll() {
        do {
            let shareItems = try exportService.shareItemsForRenderedRoll(roll)
            shareSheetPayload = ShareSheetPayload(items: shareItems)
        } catch {
            feedbackNotice = UserFeedbackNotice(
                title: "Share Failed",
                message: error.localizedDescription
            )
        }
    }

    func exportPhoto(_ item: RevealPhotoItem) {
        guard let image = item.image else {
            feedbackNotice = UserFeedbackNotice(
                title: "Export Failed",
                message: ExportServiceError.photoUnavailable.localizedDescription
            )
            return
        }

        isExporting = true

        Task {
            defer {
                isExporting = false
            }

            do {
                try await exportService.exportRenderedPhotoToLibrary(
                    image,
                    roll: roll,
                    exposureNumber: item.photo.exposureNumber
                )
                feedbackNotice = UserFeedbackNotice(
                    title: "Saved to Photos",
                    message: "The rendered photo was exported to your library."
                )
            } catch {
                feedbackNotice = UserFeedbackNotice(
                    title: "Export Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func sharePhoto(_ item: RevealPhotoItem) {
        guard let image = item.image else {
            feedbackNotice = UserFeedbackNotice(
                title: "Share Failed",
                message: ExportServiceError.photoUnavailable.localizedDescription
            )
            return
        }

        do {
            let shareItems = try exportService.shareItemsForRenderedPhoto(
                image,
                roll: roll,
                exposureNumber: item.photo.exposureNumber
            )
            shareSheetPayload = ShareSheetPayload(items: shareItems)
        } catch {
            feedbackNotice = UserFeedbackNotice(
                title: "Share Failed",
                message: error.localizedDescription
            )
        }
    }

    private func loadPhotos() {
        isLoading = true
        statusMessage = nil

        Task {
            await loadPhotosIfNeeded()
            isLoading = false
        }
    }

    private func loadPhotosIfNeeded() async {
        photoItems = localStorageService.loadPhotos()
            .filter { $0.rollID == roll.id }
            .sorted {
                if $0.exposureNumber == $1.exposureNumber {
                    return $0.createdAt < $1.createdAt
                }

                return $0.exposureNumber < $1.exposureNumber
            }
            .map { photo in
                let originalImage = photoStorageService.loadImage(at: photo.localPath)
                let processedImage = originalImage.map {
                    photoRenderService.renderedImage(
                        for: $0,
                        filmStock: roll.film,
                        cacheKey: photo.localPath
                    )
                }

                return RevealPhotoItem(
                    id: photo.id,
                    photo: photo,
                    image: processedImage ?? originalImage
                )
            }
    }

    private func persistRevealedRoll() throws -> Roll {
        let previousRolls = localStorageService.loadRolls()
        let updatedRoll = roll.markingRevealed()

        guard let rollIndex = previousRolls.firstIndex(where: { $0.id == roll.id }) else {
            throw RevealPersistenceError.rollNotFound
        }

        var updatedRolls = previousRolls
        updatedRolls[rollIndex] = updatedRoll
        try localStorageService.saveRolls(updatedRolls)
        return updatedRoll
    }
}

enum RevealPersistenceError: LocalizedError {
    case rollNotFound

    var errorDescription: String? {
        switch self {
        case .rollNotFound:
            return "This roll could not be opened."
        }
    }
}
