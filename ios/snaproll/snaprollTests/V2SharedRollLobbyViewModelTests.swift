import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2SharedRollLobbyViewModelTests {
    @Test
    func lobbyLoadsParticipantsFromRepository() async {
        let creatorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let rollID = UUID()
        let roll = LocalRoll(
            id: rollID,
            title: "Shared Summer",
            type: .shared,
            status: .waitingForParticipants,
            film_stock_id: FilmStock.kodakGold200.rawValue,
            exposures_per_participant: 12,
            creator_id: creatorID,
            created_at: .now
        )
        let participants = [
            LocalParticipant(
                id: UUID(),
                roll_id: rollID,
                user_id: creatorID,
                display_name: "Creator",
                status: .joined,
                joined_at: .now
            ),
            LocalParticipant(
                id: UUID(),
                roll_id: rollID,
                user_id: UUID(),
                display_name: "Participant A",
                status: .joined,
                joined_at: .now
            )
        ]

        let viewModel = V2SharedRollLobbyViewModel(
            rollID: rollID,
            authRepository: LobbyFakeAuthRepository(
                session: AuthSession(userID: creatorID, displayName: "Creator")
            ),
            rollRepository: LobbyFakeRollRepository(rolls: [roll]),
            participantRepository: LobbyFakeParticipantRepository(
                participantsByRollID: [rollID: participants]
            ),
            inviteRepository: LobbyFakeInviteRepository(
                invitesByRollID: [rollID: LocalInvite(id: UUID(), roll_id: rollID, token: "TOKEN123", is_active: true, created_at: .now)]
            )
        )

        await viewModel.load()

        #expect(viewModel.participants.count == 2)
        #expect(viewModel.participants.first?.display_name == "Creator")
        #expect(viewModel.state == .loaded)
    }

    @Test
    func creatorLobbyShowsInviteToken() async {
        let creatorID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let rollID = UUID()
        let roll = LocalRoll(
            id: rollID,
            title: "Creator Roll",
            type: .shared,
            status: .waitingForParticipants,
            film_stock_id: FilmStock.kodakGold200.rawValue,
            exposures_per_participant: 12,
            creator_id: creatorID,
            created_at: .now
        )
        let invite = LocalInvite(
            id: UUID(),
            roll_id: rollID,
            token: "CREATOR-TOKEN",
            is_active: true,
            created_at: .now
        )

        let viewModel = V2SharedRollLobbyViewModel(
            rollID: rollID,
            authRepository: LobbyFakeAuthRepository(
                session: AuthSession(userID: creatorID, displayName: "Creator")
            ),
            rollRepository: LobbyFakeRollRepository(rolls: [roll]),
            participantRepository: LobbyFakeParticipantRepository(
                participantsByRollID: [rollID: []]
            ),
            inviteRepository: LobbyFakeInviteRepository(
                invitesByRollID: [rollID: invite]
            )
        )

        await viewModel.load()

        #expect(viewModel.isCreator)
        #expect(viewModel.visibleInviteToken == "CREATOR-TOKEN")
    }

    @Test
    func nonCreatorLobbyHidesInviteToken() async {
        let creatorID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let participantID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let rollID = UUID()
        let roll = LocalRoll(
            id: rollID,
            title: "Joined Roll",
            type: .shared,
            status: .waitingForParticipants,
            film_stock_id: FilmStock.kodakGold200.rawValue,
            exposures_per_participant: 12,
            creator_id: creatorID,
            created_at: .now
        )

        let viewModel = V2SharedRollLobbyViewModel(
            rollID: rollID,
            authRepository: LobbyFakeAuthRepository(
                session: AuthSession(userID: participantID, displayName: "Participant A")
            ),
            rollRepository: LobbyFakeRollRepository(rolls: [roll]),
            participantRepository: LobbyFakeParticipantRepository(
                participantsByRollID: [rollID: []]
            ),
            inviteRepository: LobbyFakeInviteRepository(
                invitesByRollID: [rollID: LocalInvite(id: UUID(), roll_id: rollID, token: "HIDDEN", is_active: true, created_at: .now)]
            )
        )

        await viewModel.load()

        #expect(viewModel.isCreator == false)
        #expect(viewModel.visibleInviteToken == nil)
    }
}

private actor LobbyFakeAuthRepository: AuthRepository {
    private let session: AuthSession?

    init(session: AuthSession?) {
        self.session = session
    }

    func currentSession() async throws -> AuthSession? {
        session
    }

    func currentUserID() async throws -> UUID? {
        session?.userID
    }

    func signOut() async throws {}
}

private actor LobbyFakeRollRepository: RollRepository {
    private let rollsByID: [UUID: LocalRoll]

    init(rolls: [LocalRoll]) {
        self.rollsByID = Dictionary(uniqueKeysWithValues: rolls.map { ($0.id, $0) })
    }

    func fetchRoll(id: UUID) async throws -> LocalRoll? {
        rollsByID[id]
    }

    func fetchRolls() async throws -> [LocalRoll] {
        Array(rollsByID.values)
    }

    func fetchAllRolls() async throws -> [LocalRoll] {
        try await fetchRolls()
    }

    func startRoll(id: UUID) async throws {}
    func revealRoll(id: UUID) async throws {}

    func createRoll(
        title: String,
        type: V2Domain.RollType,
        filmStockID: String,
        exposuresPerParticipant: Int,
        participantCap: Int
    ) async throws -> CreateRollResult {
        CreateRollResult(rollID: UUID(), inviteToken: nil)
    }

    func saveRoll(_ roll: LocalRoll) async throws {}
    func deleteRoll(id: UUID) async throws {}
}

private actor LobbyFakeParticipantRepository: ParticipantRepository {
    private let participantsByRollID: [UUID: [LocalParticipant]]

    init(participantsByRollID: [UUID: [LocalParticipant]]) {
        self.participantsByRollID = participantsByRollID
    }

    func fetchParticipants(forRollID rollID: UUID) async throws -> [LocalParticipant] {
        participantsByRollID[rollID] ?? []
    }

    func fetchParticipant(id: UUID) async throws -> LocalParticipant? { nil }
    func joinRoll(inviteToken: String) async throws -> JoinRollResult {
        JoinRollResult(rollID: UUID(), participantID: UUID())
    }
    func leaveRoll(rollID: UUID) async throws {}
    func saveParticipant(_ participant: LocalParticipant) async throws {}
    func deleteParticipant(id: UUID) async throws {}
}

private actor LobbyFakeInviteRepository: InviteRepository {
    private let invitesByRollID: [UUID: LocalInvite]

    init(invitesByRollID: [UUID: LocalInvite]) {
        self.invitesByRollID = invitesByRollID
    }

    func fetchInvite(forRollID rollID: UUID) async throws -> LocalInvite? {
        invitesByRollID[rollID]
    }

    func fetchInvite(token: String) async throws -> LocalInvite? {
        invitesByRollID.values.first(where: { $0.token == token })
    }

    func regenerateInvite(forRollID rollID: UUID) async throws -> LocalInvite {
        guard let invite = invitesByRollID[rollID] else {
            throw V2RepositoryError.notFound("Invite not found.")
        }

        return invite
    }

    func saveInvite(_ invite: LocalInvite) async throws {}
    func deleteInvite(id: UUID) async throws {}
}
