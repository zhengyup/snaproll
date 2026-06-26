import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var rolls: [Roll] = []

    var activeRoll: Roll? {
        rolls.first(where: { !$0.isRevealed }) ?? rolls.first
    }

    var archivedRolls: [Roll] {
        Array(rolls.dropFirst())
    }

    var activeRollCount: Int {
        rolls.filter { !$0.isRevealed }.count
    }

    private let localStorageService: LocalStorageService
    private let photoStorageService: PhotoStorageService

    init(
        localStorageService: LocalStorageService? = nil,
        photoStorageService: PhotoStorageService? = nil
    ) {
        let storageService = localStorageService ?? LocalStorageService()
        self.localStorageService = storageService
        self.photoStorageService = photoStorageService ?? PhotoStorageService()
        rolls = storageService.loadRolls()
    }

    func reload() {
        rolls = localStorageService.loadRolls()
    }

    func createRoll(name: String, film: FilmStock, shotLimit: Int) -> Roll {
        let roll = Roll(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            film: film,
            shotLimit: shotLimit,
            createdAt: .now
        )

        rolls.insert(roll, at: 0)
        try? localStorageService.saveRolls(rolls)
        return roll
    }

    func updateRoll(_ updatedRoll: Roll) {
        guard let index = rolls.firstIndex(where: { $0.id == updatedRoll.id }) else {
            return
        }

        rolls[index] = updatedRoll
        rolls.sort { $0.createdAt > $1.createdAt }
        try? localStorageService.saveRolls(rolls)
    }

    func deleteRoll(id: UUID) {
        let photosToDelete = localStorageService.loadPhotos().filter { $0.rollID == id }
        let updatedPhotos = localStorageService.loadPhotos().filter { $0.rollID != id }
        let updatedRolls = rolls.filter { $0.id != id }

        for photo in photosToDelete {
            try? photoStorageService.deletePhoto(at: photo.localPath)
        }

        rolls = updatedRolls
        try? localStorageService.savePhotos(updatedPhotos)
        try? localStorageService.saveRolls(updatedRolls)
    }
}
