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
    @Published private(set) var isJoiningRoll = false
    @Published private(set) var lastCreatedSharedInviteToken: String?
    @Published private(set) var lastCreatedSharedRollTitle: String?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var actionStatusMessage: String?
    @Published var draftTitle = ""
    @Published var joinInviteToken = ""
    @Published var selectedCreationType: V2Domain.RollType = .personal

    private let authRepository: any AuthRepository
    private let rollRepository: any RollRepository
    private let participantRepository: any ParticipantRepository

    init(
        authRepository: any AuthRepository,
        rollRepository: any RollRepository,
        participantRepository: any ParticipantRepository
    ) {
        self.authRepository = authRepository
        self.rollRepository = rollRepository
        self.participantRepository = participantRepository
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

    func createRoll() async {
        guard !isCreatingRoll else {
            return
        }

        isCreatingRoll = true
        defer { isCreatingRoll = false }
        actionErrorMessage = nil
        actionStatusMessage = nil
        lastCreatedSharedInviteToken = nil
        lastCreatedSharedRollTitle = nil

        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "Untitled Roll" : trimmedTitle
        let type = selectedCreationType

        do {
            let result = try await rollRepository.createRoll(
                title: title,
                type: type,
                filmStockID: FilmStock.kodakGold200.rawValue,
                exposuresPerParticipant: 12,
                participantCap: type == .shared ? 10 : 1
            )

            draftTitle = ""
            if type == .shared {
                lastCreatedSharedInviteToken = result.inviteToken
                lastCreatedSharedRollTitle = title
                actionStatusMessage = result.inviteToken == nil
                    ? "Shared roll created."
                    : "Shared roll created. Invite token ready to share."
            } else {
                actionStatusMessage = "Personal roll created."
            }

            await load()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func createPersonalRoll() async {
        selectedCreationType = .personal
        await createRoll()
    }

    func createSharedRoll() async {
        selectedCreationType = .shared
        await createRoll()
    }

    func joinSharedRoll() async {
        guard !isJoiningRoll else {
            return
        }

        let trimmedToken = joinInviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            actionErrorMessage = "Enter an invite token to join a shared roll."
            actionStatusMessage = nil
            return
        }

        isJoiningRoll = true
        defer { isJoiningRoll = false }
        actionErrorMessage = nil
        actionStatusMessage = nil

        do {
            let result = try await participantRepository.joinRoll(inviteToken: trimmedToken)
            joinInviteToken = ""
            actionStatusMessage = "Joined shared roll \(result.rollID.uuidString.prefix(8))."
            await load()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}
