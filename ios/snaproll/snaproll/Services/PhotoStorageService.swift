import Foundation
import UIKit

final class PhotoStorageService {
    private let fileManager: FileManager

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

    func deletePhoto(at localPath: String) throws {
        let fileURL = URL(fileURLWithPath: localPath)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    func loadImage(at localPath: String) -> UIImage? {
        guard fileManager.fileExists(atPath: localPath) else {
            return nil
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)) else {
            return nil
        }

        return UIImage(data: data)
    }

    private func rollDirectoryURL(for rollID: UUID) throws -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let snaprollDirectory = baseDirectory.appendingPathComponent("Snaproll", isDirectory: true)
        let rollsDirectory = snaprollDirectory.appendingPathComponent("Rolls", isDirectory: true)
        let rollDirectory = rollsDirectory.appendingPathComponent(rollID.uuidString, isDirectory: true)

        try fileManager.createDirectory(at: rollDirectory, withIntermediateDirectories: true)
        return rollDirectory
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
