import Foundation

final class LocalStorageService {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadRolls() -> [Roll] {
        do {
            return try loadRollsForIntegrityCheck()
        } catch {
            return []
        }
    }

    func saveRolls(_ rolls: [Roll]) throws {
        let data = try encoder.encode(rolls)
        try data.write(to: rollsFileURL, options: .atomic)
    }

    func loadPhotos() -> [Photo] {
        do {
            return try loadPhotosForIntegrityCheck()
        } catch {
            return []
        }
    }

    func savePhotos(_ photos: [Photo]) throws {
        let data = try encoder.encode(photos)
        try data.write(to: photosFileURL, options: .atomic)
    }

    func loadRollsForIntegrityCheck() throws -> [Roll] {
        guard fileManager.fileExists(atPath: rollsFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: rollsFileURL)
        return try decoder.decode([Roll].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    func loadPhotosForIntegrityCheck() throws -> [Photo] {
        guard fileManager.fileExists(atPath: photosFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: photosFileURL)
        return try decoder.decode([Photo].self, from: data)
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var rollsFileURL: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return documentsDirectory.appendingPathComponent("rolls.json")
    }

    private var photosFileURL: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return documentsDirectory.appendingPathComponent("photos.json")
    }
}
