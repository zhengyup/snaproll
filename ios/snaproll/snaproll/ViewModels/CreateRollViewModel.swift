import Combine
import Foundation

@MainActor
final class CreateRollViewModel: ObservableObject {
    @Published var name = ""
    @Published var shotLimit = AppConfig.Rolls.defaultShotLimit
    @Published var selectedFilm: FilmStock = .kodakGold200

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
