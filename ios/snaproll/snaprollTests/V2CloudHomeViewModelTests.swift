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
            rollRepository: RecordingFakeRollRepository(fetchResults: [.success([creatorRoll])])
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
            rollRepository: rollRepository
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
            rollRepository: rollRepository
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
            )
        )

        await viewModel.load()

        guard case .failed(let message) = viewModel.state else {
            Issue.record("Expected failed state but got \(viewModel.state)")
            return
        }

        #expect(message == "Fetch failed.")
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

    init(fetchResults: [Result<[LocalRoll], Error>]) {
        self.fetchResults = fetchResults
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

        return CreateRollResult(rollID: UUID(), inviteToken: nil)
    }

    func saveRoll(_ roll: LocalRoll) async throws {}
    func deleteRoll(id: UUID) async throws {}
}
