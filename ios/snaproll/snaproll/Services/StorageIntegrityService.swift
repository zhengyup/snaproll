import Foundation

struct StorageReconciliationSummary {
    let removedOrphanedFilesCount: Int
    let removedMissingMetadataCount: Int
    let updatedRollCount: Int

    var madeChanges: Bool {
        removedOrphanedFilesCount > 0 || removedMissingMetadataCount > 0 || updatedRollCount > 0
    }
}

final class StorageIntegrityService {
    private let localStorageService: LocalStorageService
    private let fileManager: FileManager
    private let photoStorageService: PhotoStorageService

    init(
        localStorageService: LocalStorageService = LocalStorageService(),
        fileManager: FileManager = .default,
        photoStorageService: PhotoStorageService = PhotoStorageService()
    ) {
        self.localStorageService = localStorageService
        self.fileManager = fileManager
        self.photoStorageService = photoStorageService
    }

    @discardableResult
    func reconcile() -> StorageReconciliationSummary {
        let rolls: [Roll]
        let photos: [Photo]

        do {
            rolls = try localStorageService.loadRollsForIntegrityCheck()
            photos = try localStorageService.loadPhotosForIntegrityCheck()
        } catch {
            // If storage can't be read confidently, do not mutate anything.
            return StorageReconciliationSummary(
                removedOrphanedFilesCount: 0,
                removedMissingMetadataCount: 0,
                updatedRollCount: 0
            )
        }

        let validRollIDs = Set(rolls.map(\.id))

        var keptPhotos: [Photo] = []
        var removedMissingMetadataCount = 0

        for photo in photos {
            guard validRollIDs.contains(photo.rollID) else {
                try? photoStorageService.deletePhoto(at: photo.localPath)
                removedMissingMetadataCount += 1
                continue
            }

            keptPhotos.append(
                Photo(
                    id: photo.id,
                    rollID: photo.rollID,
                    localPath: photoStorageService.normalizedLocalPath(photo.localPath),
                    createdAt: photo.createdAt,
                    exposureNumber: photo.exposureNumber
                )
            )
        }

        let removedOrphanedFilesCount = removeFilesForMissingRolls(validRollIDs: validRollIDs)

        if keptPhotos != photos {
            try? localStorageService.savePhotos(keptPhotos)
        }

        let reconciledRolls = reconcileRolls(rolls, photos: keptPhotos)
        let updatedRollCount = zip(rolls, reconciledRolls).filter { $0 != $1 }.count

        if updatedRollCount > 0 {
            try? localStorageService.saveRolls(reconciledRolls)
        }

        return StorageReconciliationSummary(
            removedOrphanedFilesCount: removedOrphanedFilesCount,
            removedMissingMetadataCount: removedMissingMetadataCount,
            updatedRollCount: updatedRollCount
        )
    }

    private func reconcileRolls(_ rolls: [Roll], photos: [Photo]) -> [Roll] {
        let photosByRoll = Dictionary(grouping: photos, by: \.rollID)

        return rolls.map { roll in
            let rollPhotos = photosByRoll[roll.id] ?? []
            let persistedExposureCount = min(roll.shotLimit, roll.exposuresUsed)
            let metadataExposureCount = min(roll.shotLimit, rollPhotos.count)
            let reconciledExposureCount = max(persistedExposureCount, metadataExposureCount)

            if roll.isRevealed {
                return Roll(
                    id: roll.id,
                    name: roll.name,
                    film: roll.film,
                    shotLimit: roll.shotLimit,
                    exposuresUsed: reconciledExposureCount,
                    status: .revealed,
                    createdAt: roll.createdAt
                )
            }

            let reconciledStatus: RollStatus = reconciledExposureCount >= roll.shotLimit ? .completed : .inProgress

            return Roll(
                id: roll.id,
                name: roll.name,
                film: roll.film,
                shotLimit: roll.shotLimit,
                exposuresUsed: reconciledExposureCount,
                status: reconciledStatus,
                createdAt: roll.createdAt
            )
        }
    }

    private func removeFilesForMissingRolls(validRollIDs: Set<UUID>) -> Int {
        let rootDirectory = storageRootDirectoryURL()

        guard let rollDirectories = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var removedFileCount = 0

        for directoryURL in rollDirectories {
            let directoryName = directoryURL.lastPathComponent

            guard let rollID = UUID(uuidString: directoryName) else {
                removedFileCount += removeDirectoryAndCountFiles(at: directoryURL)
                continue
            }

            guard !validRollIDs.contains(rollID) else {
                continue
            }

            removedFileCount += removeDirectoryAndCountFiles(at: directoryURL)
        }

        return removedFileCount
    }

    private func removeDirectoryAndCountFiles(at directoryURL: URL) -> Int {
        let fileCount: Int

        if let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            fileCount = enumerator.compactMap { $0 as? URL }.count
        } else {
            fileCount = 0
        }

        try? fileManager.removeItem(at: directoryURL)
        return fileCount
    }

    private func storageRootDirectoryURL() -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return baseDirectory
            .appendingPathComponent("Snaproll", isDirectory: true)
            .appendingPathComponent("Rolls", isDirectory: true)
    }
}
