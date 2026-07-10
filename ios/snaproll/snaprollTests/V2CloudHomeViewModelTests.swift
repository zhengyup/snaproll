import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2CloudHomeViewModelTests {
    @Test
    func loadsRollsForCurrentIdentity() async {
        let creatorSession = AuthSession(
            userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            displayName: "Creator"
        )
        let creatorRoll = LocalRoll(
            id: UUID(),
            title: "Creator Roll",
            type: .personal,
            status: .draft,
            film_stock_id: FilmStock.kodakGold200.rawValue,
            exposures_per_participant: 12,
            creator_id: creatorSession.userID,
            created_at: .now
        )
        let viewModel = V2CloudHomeViewModel(
            authRepository: MutableFakeAuthRepository(session: creatorSession),
            rollRepository: RecordingFakeRollRepository(fetchResults: [.success([creatorRoll])]),
            participantRepository: RecordingFakeParticipantRepository()
        )

        await viewModel.load()

        #expect(viewModel.currentSession == creatorSession)
        #expect(viewModel.rolls.count == 1)
        #expect(viewModel.rolls.first?.title == "Creator Roll")
        #expect(viewModel.state == .loaded)
    }

    @Test
    func createPersonalRollUsesPersonalTypeAndDefaults() async {
        let creatorSession = AuthSession(
            userID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            displayName: "Creator"
        )
        let rollRepository = RecordingFakeRollRepository(
            fetchResults: [
                .success([]),
                .success([
                    LocalRoll(
                        id: UUID(),
                        title: "Untitled Roll",
                        type: .personal,
                        status: .draft,
                        film_stock_id: FilmStock.kodakGold200.rawValue,
                        exposures_per_participant: 12,
                        creator_id: creatorSession.userID,
                        created_at: .now
                    )
                ])
            ]
        )
        let viewModel = V2CloudHomeViewModel(
            authRepository: MutableFakeAuthRepository(session: creatorSession),
            rollRepository: rollRepository,
            participantRepository: RecordingFakeParticipantRepository()
        )

        await viewModel.load()
        await viewModel.createPersonalRoll()

        let createCall = await rollRepository.lastCreateCall
        #expect(createCall?.title == "Untitled Roll")
        #expect(createCall?.type == .personal)
        #expect(createCall?.filmStockID == FilmStock.kodakGold200.rawValue)
        #expect(createCall?.exposuresPerParticipant == 12)
        #expect(createCall?.participantCap == 1)
    }

    @Test
    func reloadingAfterIdentityChangeShowsDifferentUserScopedRolls() async {
        let authRepository = MutableFakeAuthRepository(
            session: AuthSession(
                userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                displayName: "Creator"
            )
        )
        let creatorRoll = LocalRoll(
            id: UUID(),
            title: "Creator Only",
            type: .personal,
            status: .draft,
            film_stock_id: FilmStock.kodakGold200.rawValue,
            exposures_per_participant: 12,
            creator_id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            created_at: .now
        )
        let participantRoll = LocalRoll(
            id: UUID(),
            title: "Participant A Only",
            type: .personal,
            status: .draft,
            film_stock_id: FilmStock.kodakGold200.rawValue,
            exposures_per_participant: 12,
            creator_id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            created_at: .now
        )
        let rollRepository = RecordingFakeRollRepository(
            fetchResults: [
                .success([creatorRoll]),
                .success([participantRoll])
            ]
        )
        let viewModel = V2CloudHomeViewModel(
            authRepository: authRepository,
            rollRepository: rollRepository,
            participantRepository: RecordingFakeParticipantRepository()
        )

        await viewModel.load()
        #expect(viewModel.rolls.first?.title == "Creator Only")

        await authRepository.setSession(
            AuthSession(
                userID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                displayName: "Participant A"
            )
        )

        await viewModel.load()
        #expect(viewModel.currentSession?.displayName == "Participant A")
        #expect(viewModel.rolls.first?.title == "Participant A Only")
    }

    @Test
    func repositoryErrorsSurfaceAsFailedState() async {
        let viewModel = V2CloudHomeViewModel(
            authRepository: MutableFakeAuthRepository(
                session: AuthSession(userID: UUID(), displayName: "Creator")
            ),
            rollRepository: RecordingFakeRollRepository(
                fetchResults: [.failure(V2RepositoryError.network("Fetch failed."))]
            ),
            participantRepository: RecordingFakeParticipantRepository()
        )

        await viewModel.load()

        guard case .failed(let message) = viewModel.state else {
            Issue.record("Expected failed state but got \(viewModel.state)")
            return
        }

        #expect(message == "Fetch failed.")
    }

    @Test
    func createSharedRollUsesSharedTypeAndStoresInviteToken() async {
        let creatorSession = AuthSession(
            userID: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            displayName: "Creator"
        )
        let sharedRoll = LocalRoll(
            id: UUID(),
            title: "Weekend Crew",
            type: .shared,
            status: .waitingForParticipants,
            film_stock_id: FilmStock.kodakGold200.rawValue,
            exposures_per_participant: 12,
            creator_id: creatorSession.userID,
            created_at: .now
        )
        let rollRepository = RecordingFakeRollRepository(
            fetchResults: [
                .success([]),
                .success([sharedRoll])
            ],
            createResults: [
                CreateRollResult(rollID: sharedRoll.id, inviteToken: "SHARED-TOKEN")
            ]
        )
        let viewModel = V2CloudHomeViewModel(
            authRepository: MutableFakeAuthRepository(session: creatorSession),
            rollRepository: rollRepository,
            participantRepository: RecordingFakeParticipantRepository()
        )
        viewModel.selectedCreationType = .shared
        viewModel.draftTitle = "Weekend Crew"

        await viewModel.load()
        await viewModel.createRoll()

        let createCall = await rollRepository.lastCreateCall
        #expect(createCall?.type == .shared)
        #expect(createCall?.participantCap == 10)
        #expect(viewModel.lastCreatedSharedInviteToken == "SHARED-TOKEN")
    }

    @Test
    func joinRollCallsParticipantRepositoryWithTokenAndRefreshesRolls() async {
        let creatorSession = AuthSession(
            userID: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            displayName: "Participant A"
        )
        let joinedRoll = LocalRoll(
            id: UUID(),
            title: "Shared Roll",
            type: .shared,
            status: .waitingForParticipants,
            film_stock_id: FilmStock.kodakGold200.rawValue,
            exposures_per_participant: 12,
            creator_id: UUID(),
            created_at: .now
        )
        let participantRepository = RecordingFakeParticipantRepository(
            joinResults: [.success(JoinRollResult(rollID: joinedRoll.id, participantID: UUID()))]
        )
        let rollRepository = RecordingFakeRollRepository(
            fetchResults: [
                .success([]),
                .success([joinedRoll])
            ]
        )
        let viewModel = V2CloudHomeViewModel(
            authRepository: MutableFakeAuthRepository(session: creatorSession),
            rollRepository: rollRepository,
            participantRepository: participantRepository
        )
        viewModel.joinInviteToken = "JOIN-TOKEN"

        await viewModel.load()
        await viewModel.joinSharedRoll()

        let lastJoinToken = await participantRepository.lastJoinInviteToken
        #expect(lastJoinToken == "JOIN-TOKEN")
        #expect(viewModel.rolls.first?.title == "Shared Roll")
    }

    @Test
    func joinErrorSurfacesReadableState() async {
        let participantRepository = RecordingFakeParticipantRepository(
            joinResults: [.failure(V2RepositoryError.businessRuleViolation("Already joined this roll."))]
        )
        let viewModel = V2CloudHomeViewModel(
            authRepository: MutableFakeAuthRepository(
                session: AuthSession(userID: UUID(), displayName: "Participant A")
            ),
            rollRepository: RecordingFakeRollRepository(fetchResults: [.success([])]),
            participantRepository: participantRepository
        )
        viewModel.joinInviteToken = "DUPLICATE"

        await viewModel.joinSharedRoll()

        #expect(viewModel.actionErrorMessage == "Already joined this roll.")
    }
}

private actor MutableFakeAuthRepository: AuthRepository {
    private var session: AuthSession?

    init(session: AuthSession?) {
        self.session = session
    }

    func currentSession() async throws -> AuthSession? {
        session
    }

    func currentUserID() async throws -> UUID? {
        let session = self.session
        return await MainActor.run { session?.userID }
    }

    func signOut() async throws {
        session = nil
    }

    func setSession(_ session: AuthSession?) {
        self.session = session
    }
}

private actor RecordingFakeRollRepository: RollRepository {
    struct CreateCall: Equatable {
        let title: String
        let type: V2Domain.RollType
        let filmStockID: String
        let exposuresPerParticipant: Int
        let participantCap: Int
    }

    private(set) var lastCreateCall: CreateCall?
    private var fetchResults: [Result<[LocalRoll], Error>]
    private var createResults: [CreateRollResult]

    init(
        fetchResults: [Result<[LocalRoll], Error>],
        createResults: [CreateRollResult] = []
    ) {
        self.fetchResults = fetchResults
        self.createResults = createResults
    }

    func fetchRoll(id: UUID) async throws -> LocalRoll? {
        let rolls = try await fetchRolls()
        return await MainActor.run {
            rolls.first { $0.id == id }
        }
    }

    func fetchRolls() async throws -> [LocalRoll] {
        guard !fetchResults.isEmpty else {
            return []
        }

        let result = fetchResults.removeFirst()
        return try result.get()
    }

    func fetchAllRolls() async throws -> [LocalRoll] {
        try await fetchRolls()
    }

    func createRoll(
        title: String,
        type: V2Domain.RollType,
        filmStockID: String,
        exposuresPerParticipant: Int,
        participantCap: Int
    ) async throws -> CreateRollResult {
        lastCreateCall = CreateCall(
            title: title,
            type: type,
            filmStockID: filmStockID,
            exposuresPerParticipant: exposuresPerParticipant,
            participantCap: participantCap
        )

        if !createResults.isEmpty {
            return createResults.removeFirst()
        }

        return CreateRollResult(rollID: UUID(), inviteToken: nil)
    }

    func startRoll(id: UUID) async throws {}
    func revealRoll(id: UUID) async throws {}

    func saveRoll(_ roll: LocalRoll) async throws {}
    func deleteRoll(id: UUID) async throws {}
}

private actor RecordingFakeParticipantRepository: ParticipantRepository {
    private(set) var lastJoinInviteToken: String?
    private let participantsByRollID: [UUID: [LocalParticipant]]
    private var joinResults: [Result<JoinRollResult, Error>]

    init(
        participantsByRollID: [UUID: [LocalParticipant]] = [:],
        joinResults: [Result<JoinRollResult, Error>] = []
    ) {
        self.participantsByRollID = participantsByRollID
        self.joinResults = joinResults
    }

    func fetchParticipants(forRollID rollID: UUID) async throws -> [LocalParticipant] {
        participantsByRollID[rollID] ?? []
    }

    func fetchParticipant(id: UUID) async throws -> LocalParticipant? { nil }

    func joinRoll(inviteToken: String) async throws -> JoinRollResult {
        lastJoinInviteToken = inviteToken

        if !joinResults.isEmpty {
            return try joinResults.removeFirst().get()
        }

        return JoinRollResult(rollID: UUID(), participantID: UUID())
    }

    func leaveRoll(rollID: UUID) async throws {}
    func saveParticipant(_ participant: LocalParticipant) async throws {}
    func deleteParticipant(id: UUID) async throws {}
}

private actor RecordingFakeInviteRepository: InviteRepository {
    private let invitesByRollID: [UUID: LocalInvite]

    init(invitesByRollID: [UUID: LocalInvite] = [:]) {
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
