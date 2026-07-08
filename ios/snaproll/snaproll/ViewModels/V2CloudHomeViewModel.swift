import Combine
import Foundation

enum V2CloudHomeState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case signedOut
    case failed(String)
}

@MainActor
final class V2CloudHomeViewModel: ObservableObject {
    @Published private(set) var state: V2CloudHomeState = .idle
    @Published private(set) var currentSession: AuthSession?
    @Published private(set) var rolls: [LocalRoll] = []
    @Published private(set) var isCreatingRoll = false
    @Published var draftTitle = ""

    private let authRepository: any AuthRepository
    private let rollRepository: any RollRepository

    init(
        authRepository: any AuthRepository,
        rollRepository: any RollRepository
    ) {
        self.authRepository = authRepository
        self.rollRepository = rollRepository
    }

    func load() async {
        state = .loading

        do {
            guard let session = try await authRepository.currentSession() else {
                currentSession = nil
                rolls = []
                state = .signedOut
                return
            }

            currentSession = session
            rolls = try await rollRepository.fetchRolls()
            state = rolls.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        await load()
    }

    func createPersonalRoll() async {
        guard !isCreatingRoll else {
            return
        }

        isCreatingRoll = true
        defer { isCreatingRoll = false }

        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "Untitled Roll" : trimmedTitle

        do {
            _ = try await rollRepository.createRoll(
                title: title,
                type: .personal,
                filmStockID: FilmStock.kodakGold200.rawValue,
                exposuresPerParticipant: 12,
                participantCap: 1
            )

            draftTitle = ""
            await load()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
