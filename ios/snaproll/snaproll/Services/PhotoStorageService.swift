import Foundation
import UIKit

final class PhotoStorageService {
    private let fileManager: FileManager
    private let legacyStoragePathMarker = "/Snaproll/Rolls/"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func savePhotoData(_ data: Data, for rollID: UUID, photoID: UUID) throws -> URL {
        guard let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: AppConfig.Photos.jpegCompressionQuality) else {
            throw PhotoStorageServiceError.compressionFailed
        }

        let rollDirectory = try rollDirectoryURL(for: rollID)
        let fileURL = rollDirectory.appendingPathComponent("\(photoID.uuidString).jpg")
        try jpegData.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func saveOriginalImageData(
        _ data: Data,
        for rollID: UUID,
        exposureID: UUID,
        preferredFileExtension: String? = nil
    ) throws -> URL {
        let fileExtension = preferredFileExtension ?? fileExtension(forImageData: data) ?? "jpg"
        let rollDirectory = try rollDirectoryURL(for: rollID)
        let fileURL = rollDirectory.appendingPathComponent("\(exposureID.uuidString).\(fileExtension)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func persistentLocalPath(for fileURL: URL) -> String {
        let storageRoot = storageRootDirectoryURL().path
        let filePath = fileURL.path

        guard filePath.hasPrefix(storageRoot + "/") else {
            return filePath
        }

        return String(filePath.dropFirst(storageRoot.count + 1))
    }

    func deletePhoto(at localPath: String) throws {
        let fileURL = resolvedFileURL(for: localPath)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
 
        try fileManager.removeItem(at: fileURL)
    }

    func loadImage(at localPath: String) -> UIImage? {
        let resolvedURL = resolvedFileURL(for: localPath)

        guard fileManager.fileExists(atPath: resolvedURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: resolvedURL) else {
            return nil
        }

        return UIImage(data: data)
    }

    func normalizedLocalPath(_ localPath: String) -> String {
        let resolvedURL = resolvedFileURL(for: localPath)
        return persistentLocalPath(for: resolvedURL)
    }

    func fileExists(at localPath: String) -> Bool {
        fileManager.fileExists(atPath: resolvedFileURL(for: localPath).path)
    }

    private func rollDirectoryURL(for rollID: UUID) throws -> URL {
        let rollsDirectory = storageRootDirectoryURL()
        let rollDirectory = rollsDirectory.appendingPathComponent(rollID.uuidString, isDirectory: true)

        try fileManager.createDirectory(at: rollDirectory, withIntermediateDirectories: true)
        return rollDirectory
    }

    private func storageRootDirectoryURL() -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let snaprollDirectory = baseDirectory.appendingPathComponent("Snaproll", isDirectory: true)
        return snaprollDirectory.appendingPathComponent("Rolls", isDirectory: true)
    }

    private func resolvedFileURL(for localPath: String) -> URL {
        if localPath.hasPrefix("/") {
            let absoluteURL = URL(fileURLWithPath: localPath)

            if fileManager.fileExists(atPath: absoluteURL.path) {
                return absoluteURL
            }

            if let relativeSuffix = relativeSuffixFromLegacyAbsolutePath(localPath) {
                return storageRootDirectoryURL().appendingPathComponent(relativeSuffix, isDirectory: false)
            }

            return absoluteURL
        }

        return storageRootDirectoryURL().appendingPathComponent(localPath, isDirectory: false)
    }

    private func relativeSuffixFromLegacyAbsolutePath(_ absolutePath: String) -> String? {
        guard let markerRange = absolutePath.range(of: legacyStoragePathMarker) else {
            return nil
        }

        return String(absolutePath[markerRange.upperBound...])
    }

    private func fileExtension(forImageData data: Data) -> String? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }

        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "gif"
        }

        return nil
    }
}

enum PhotoStorageServiceError: LocalizedError {
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "The photo could not be prepared for local storage."
        }
    }
}
