import Foundation
import Photos
import UIKit

struct RollExportSummary {
    let exportedCount: Int
    let failedCount: Int
}

enum ExportPermissionState {
    case authorized
    case limited
    case denied
    case restricted
    case notDetermined

    var allowsExport: Bool {
        self == .authorized || self == .limited
    }
}

enum ExportServiceError: LocalizedError {
    case rollNotRevealed
    case photoUnavailable
    case noPhotosToExport
    case imageEncodingFailed
    case permissionDenied
    case permissionRestricted
    case exportFailed
    case sharePreparationFailed

    var errorDescription: String? {
        switch self {
        case .rollNotRevealed:
            return "Reveal the roll before exporting memories."
        case .photoUnavailable:
            return "That photo could not be prepared for export."
        case .noPhotosToExport:
            return "There are no revealed photos ready to export."
        case .imageEncodingFailed:
            return "Snaproll couldn't prepare that image for export."
        case .permissionDenied:
            return "Photo Library access was denied. Allow access in Settings to export memories."
        case .permissionRestricted:
            return "Photo Library access is restricted on this device."
        case .exportFailed:
            return "Snaproll couldn't export that memory."
        case .sharePreparationFailed:
            return "Snaproll couldn't prepare those memories to share."
        }
    }
}

final class ExportService {
    private let localStorageService: LocalStorageService
    private let photoStorageService: PhotoStorageService
    private let photoRenderService: PhotoRenderService
    private let fileManager: FileManager

    init(
        localStorageService: LocalStorageService = LocalStorageService(),
        photoStorageService: PhotoStorageService = PhotoStorageService(),
        photoRenderService: PhotoRenderService = PhotoRenderService(),
        fileManager: FileManager = .default
    ) {
        self.localStorageService = localStorageService
        self.photoStorageService = photoStorageService
        self.photoRenderService = photoRenderService
        self.fileManager = fileManager
    }

    func exportRenderedPhotoToLibrary(
        _ image: UIImage,
        roll: Roll,
        exposureNumber: Int
    ) async throws {
        try await ensurePhotoLibraryAccess()

        let photoData = try jpegData(for: image)
        let fileName = exportFileName(for: roll, exposureNumber: exposureNumber)
        try await savePhotoDataToPhotoLibrary(photoData, fileName: fileName)
    }

    func exportRenderedRollToLibrary(for roll: Roll) async throws -> RollExportSummary {
        try await ensurePhotoLibraryAccess()

        let renderedPhotos = try renderedPhotos(for: roll)
        guard !renderedPhotos.isEmpty else {
            throw ExportServiceError.noPhotosToExport
        }

        var exportedCount = 0
        var failedCount = 0

        for renderedPhoto in renderedPhotos {
            do {
                let photoData = try jpegData(for: renderedPhoto.image)
                let fileName = exportFileName(for: roll, exposureNumber: renderedPhoto.photo.exposureNumber)
                try await savePhotoDataToPhotoLibrary(photoData, fileName: fileName)
                exportedCount += 1
            } catch {
                failedCount += 1
            }
        }

        return RollExportSummary(exportedCount: exportedCount, failedCount: failedCount)
    }

    func shareItemsForRenderedPhoto(
        _ image: UIImage,
        roll: Roll,
        exposureNumber: Int
    ) throws -> [Any] {
        let fileName = exportFileName(for: roll, exposureNumber: exposureNumber)
        let exportDirectory = try prepareFreshShareExportDirectory()
        let fileURL = try writeShareFile(for: image, fileName: fileName, directory: exportDirectory)
        return [fileURL]
    }

    func shareItemsForRenderedRoll(_ roll: Roll) throws -> [Any] {
        let renderedPhotos = try renderedPhotos(for: roll)
        guard !renderedPhotos.isEmpty else {
            throw ExportServiceError.noPhotosToExport
        }

        let exportDirectory = try prepareFreshShareExportDirectory()
        let fileURLs = try renderedPhotos.map { renderedPhoto in
            let fileName = exportFileName(for: roll, exposureNumber: renderedPhoto.photo.exposureNumber)
            return try writeShareFile(for: renderedPhoto.image, fileName: fileName, directory: exportDirectory)
        }

        guard !fileURLs.isEmpty else {
            throw ExportServiceError.sharePreparationFailed
        }

        return fileURLs
    }

    private func renderedPhotos(for roll: Roll) throws -> [(photo: Photo, image: UIImage)] {
        guard roll.isRevealed else {
            throw ExportServiceError.rollNotRevealed
        }

        let photos = localStorageService.loadPhotos()
            .filter { $0.rollID == roll.id }
            .sorted {
                if $0.exposureNumber == $1.exposureNumber {
                    return $0.createdAt < $1.createdAt
                }

                return $0.exposureNumber < $1.exposureNumber
            }

        let renderedPhotos = photos.compactMap { photo -> (photo: Photo, image: UIImage)? in
            guard let originalImage = photoStorageService.loadImage(at: photo.localPath) else {
                return nil
            }

            let renderedImage = photoRenderService.renderedImage(
                for: originalImage,
                filmStock: roll.film,
                cacheKey: photo.localPath
            )

            return (photo: photo, image: renderedImage)
        }

        guard !renderedPhotos.isEmpty else {
            throw ExportServiceError.noPhotosToExport
        }

        return renderedPhotos
    }

    private func ensurePhotoLibraryAccess() async throws {
        let currentState = permissionState()

        switch currentState {
        case .authorized, .limited:
            return
        case .restricted:
            throw ExportServiceError.permissionRestricted
        case .denied:
            throw ExportServiceError.permissionDenied
        case .notDetermined:
            let requestedState = await requestPhotoLibraryPermission()
            switch requestedState {
            case .authorized, .limited:
                return
            case .restricted:
                throw ExportServiceError.permissionRestricted
            case .denied, .notDetermined:
                throw ExportServiceError.permissionDenied
            }
        }
    }

    private func permissionState() -> ExportPermissionState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    private func requestPhotoLibraryPermission() async -> ExportPermissionState {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

        switch status {
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    private func savePhotoDataToPhotoLibrary(_ data: Data, fileName: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = fileName
                creationRequest.addResource(with: .photo, data: data, options: options)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ExportServiceError.exportFailed)
                }
            }
        }
    }

    private func writeShareFile(for image: UIImage, fileName: String, directory: URL) throws -> URL {
        let photoData = try jpegData(for: image)
        let fileURL = directory.appendingPathComponent(fileName)
        try photoData.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func prepareFreshShareExportDirectory() throws -> URL {
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Snaproll", isDirectory: true)
            .appendingPathComponent("ShareExports", isDirectory: true)

        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        return baseDirectory
    }

    private func jpegData(for image: UIImage) throws -> Data {
        guard let data = image.jpegData(compressionQuality: 0.96) else {
            throw ExportServiceError.imageEncodingFailed
        }

        return data
    }

    private func exportFileName(for roll: Roll, exposureNumber: Int) -> String {
        let sanitizedRollName = roll.name
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "-")

        let clampedName = sanitizedRollName.isEmpty ? "snaproll" : sanitizedRollName
        return String(format: "%02d-%@.jpg", exposureNumber, clampedName)
    }
}
