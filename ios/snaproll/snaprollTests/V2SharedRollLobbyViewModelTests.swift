import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2SharedRollLobbyViewModelTests {
    @Test
    func creatorCanRemoveParticipant() async throws {
        let creatorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let participantAID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let rollID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let creatorParticipant = makeParticipant(id: UUID(), rollID: rollID, userID: creatorID, name: "Creator")
        let removableParticipant = makeParticipant(id: UUID(), rollID: rollID, userID: participantAID, name: "Participant A")

        let participantRepository = SharedLobbyParticipantRepository(
            participants: [creatorParticipant, removableParticipant]
        )
        let viewModel = makeViewModel(
            session: AuthSession(userID: creatorID, displayName: "Creator"),
            roll: makeSharedRoll(id: rollID, creatorID: creatorID, status: .waitingForParticipants),
            participantRepository: participantRepository
        )

        await viewModel.load()
        await viewModel.removeParticipant(id: removableParticipant.id)

        let removedIDs = await participantRepository.removedParticipantIDs
        #expect(removedIDs == [removableParticipant.id])
        #expect(viewModel.participants.count == 1)
        #expect(viewModel.actionStatusMessage == "Participant removed.")
    }

    @Test
    func participantCanLeave() async {
        let creatorID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let participantID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let rollID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let participantRepository = SharedLobbyParticipantRepository(
            participants: [
                makeParticipant(id: UUID(), rollID: rollID, userID: creatorID, name: "Creator"),
                makeParticipant(id: UUID(), rollID: rollID, userID: participantID, name: "Participant A")
            ]
        )
        let viewModel = makeViewModel(
            session: AuthSession(userID: participantID, displayName: "Participant A"),
            roll: makeSharedRoll(id: rollID, creatorID: creatorID, status: .waitingForParticipants),
            participantRepository: participantRepository
        )

        await viewModel.load()
        await viewModel.leaveRoll()

        let leftRollIDs = await participantRepository.leftRollIDs
        #expect(leftRollIDs == [rollID])
        #expect(viewModel.state == .left)
        #expect(viewModel.actionStatusMessage == "You left the roll.")
    }

    @Test
    func creatorCannotLeaveOwnRoll() async {
        let creatorID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let rollID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let viewModel = makeViewModel(
            session: AuthSession(userID: creatorID, displayName: "Creator"),
            roll: makeSharedRoll(id: rollID, creatorID: creatorID, status: .waitingForParticipants),
            participantRepository: SharedLobbyParticipantRepository(
                participants: [makeParticipant(id: UUID(), rollID: rollID, userID: creatorID, name: "Creator")]
            )
        )

        await viewModel.load()
        await viewModel.leaveRoll()

        #expect(viewModel.canLeaveRoll == false)
        #expect(viewModel.actionErrorMessage == "The creator cannot leave their own roll.")
    }

    @Test
    func regenerateInviteRefreshesInviteState() async {
        let creatorID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let rollID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let inviteRepository = SharedLobbyInviteRepository(
            invite: LocalInvite(id: UUID(), roll_id: rollID, token: "OLD-TOKEN", is_active: true, created_at: .now),
            regeneratedInvite: LocalInvite(id: UUID(), roll_id: rollID, token: "NEW-TOKEN", is_active: true, created_at: .now)
        )
        let viewModel = makeViewModel(
            session: AuthSession(userID: creatorID, displayName: "Creator"),
            roll: makeSharedRoll(id: rollID, creatorID: creatorID, status: .waitingForParticipants),
            participantRepository: SharedLobbyParticipantRepository(
                participants: [makeParticipant(id: UUID(), rollID: rollID, userID: creatorID, name: "Creator")]
            ),
            inviteRepository: inviteRepository
        )

        await viewModel.load()
        await viewModel.regenerateInvite()

        let regeneratedRollIDs = await inviteRepository.regeneratedRollIDs
        #expect(regeneratedRollIDs == [rollID])
        #expect(viewModel.visibleInviteToken == "NEW-TOKEN")
        #expect(viewModel.actionStatusMessage == "Invite regenerated.")
    }

    @Test
    func startRollInvokesRepositoryAndMirrorsCurrentParticipantExposureSlots() async throws {
        let creatorID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let rollID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let creatorParticipant = makeParticipant(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            rollID: rollID,
            userID: creatorID,
            name: "Creator"
        )
        let participantRepository = SharedLobbyParticipantRepository(participants: [creatorParticipant])
        let rollRepository = SharedLobbyRollRepository(
            roll: makeSharedRoll(id: rollID, creatorID: creatorID, status: .waitingForParticipants),
            startedRoll: makeSharedRoll(id: rollID, creatorID: creatorID, status: .shooting)
        )
        let exposures = [
            makeExposure(
                id: UUID(uuidString: "AAAAAAAA-1000-0000-0000-000000000001")!,
                rollID: rollID,
                participantID: creatorParticipant.id,
                exposureNumber: 1
            ),
            makeExposure(
                id: UUID(uuidString: "AAAAAAAA-1000-0000-0000-000000000002")!,
                rollID: rollID,
                participantID: creatorParticipant.id,
                exposureNumber: 2
            )
        ]
        let exposureRepository = SharedLobbyExposureRepository(
            exposuresByParticipantID: [creatorParticipant.id: exposures]
        )
        let mirrorStore = SharedLobbyMirrorStore()
        let viewModel = makeViewModel(
            session: AuthSession(userID: creatorID, displayName: "Creator"),
            rollRepository: rollRepository,
            roll: makeSharedRoll(id: rollID, creatorID: creatorID, status: .waitingForParticipants),
            participantRepository: participantRepository,
            exposureRepository: exposureRepository,
            exposureMirrorStore: mirrorStore
        )

        await viewModel.load()
        await viewModel.startRoll()

        let startedRollIDs = await rollRepository.startedRollIDs
        let fetchedParticipantIDs = await exposureRepository.fetchedParticipantIDs
        let mirroredExposures = try await mirrorStore.fetchExposures(forRollID: rollID)

        #expect(startedRollIDs == [rollID])
        #expect(fetchedParticipantIDs == [creatorParticipant.id])
        #expect(viewModel.roll?.status == .shooting)
        #expect(viewModel.mirroredExposureCount == 2)
        #expect(mirroredExposures.count == 2)
    }

    @Test
    func lobbyActionsBecomeUnavailableAfterShooting() async {
        let creatorID = UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!
        let rollID = UUID(uuidString: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD")!
        let creatorParticipant = makeParticipant(id: UUID(), rollID: rollID, userID: creatorID, name: "Creator")
        let viewModel = makeViewModel(
            session: AuthSession(userID: creatorID, displayName: "Creator"),
            roll: makeSharedRoll(id: rollID, creatorID: creatorID, status: .shooting),
            participantRepository: SharedLobbyParticipantRepository(participants: [creatorParticipant])
        )

        await viewModel.load()

        #expect(viewModel.isMutableLobby == false)
        #expect(viewModel.canStartRoll == false)
        #expect(viewModel.canRegenerateInvite == false)
        #expect(viewModel.canLeaveRoll == false)
        #expect(viewModel.canRemoveParticipant(creatorParticipant) == false)
    }

    @Test
    func backendErrorsSurfaceCorrectlyForInvalidOperations() async {
        let creatorID = UUID(uuidString: "EFEFEFEF-EFEF-EFEF-EFEF-EFEFEFEFEFEF")!
        let rollID = UUID(uuidString: "F0F0F0F0-F0F0-F0F0-F0F0-F0F0F0F0F0F0")!
        let removableParticipant = makeParticipant(id: UUID(), rollID: rollID, userID: UUID(), name: "Participant A")
        let participantRepository = SharedLobbyParticipantRepository(
            participants: [makeParticipant(id: UUID(), rollID: rollID, userID: creatorID, name: "Creator"), removableParticipant],
            removeError: V2RepositoryError.lifecycleViolation("Participants can only be removed before the roll starts.")
        )
        let viewModel = makeViewModel(
            session: AuthSession(userID: creatorID, displayName: "Creator"),
            roll: makeSharedRoll(id: rollID, creatorID: creatorID, status: .waitingForParticipants),
            participantRepository: participantRepository
        )

        await viewModel.load()
        await viewModel.removeParticipant(id: removableParticipant.id)

        #expect(viewModel.actionErrorMessage == "Participants can only be removed before the roll starts.")
    }
}

@MainActor
private func makeViewModel(
    session: AuthSession,
    rollRepository: SharedLobbyRollRepository? = nil,
    roll: LocalRoll,
    participantRepository: SharedLobbyParticipantRepository,
    inviteRepository: SharedLobbyInviteRepository = SharedLobbyInviteRepository(),
    exposureRepository: SharedLobbyExposureRepository = SharedLobbyExposureRepository(),
    exposureMirrorStore: SharedLobbyMirrorStore? = nil,
    diagnosticsEnabled: Bool = true
) -> V2SharedRollLobbyViewModel {
    let resolvedMirrorStore = exposureMirrorStore ?? SharedLobbyMirrorStore()

    return V2SharedRollLobbyViewModel(
        rollID: roll.id,
        authRepository: SharedLobbyAuthRepository(session: session),
        rollRepository: rollRepository ?? SharedLobbyRollRepository(roll: roll),
        participantRepository: participantRepository,
        inviteRepository: inviteRepository,
        exposureRepository: exposureRepository,
        exposureMirrorStore: resolvedMirrorStore,
        diagnosticsEnabled: diagnosticsEnabled,
        activeDevelopmentIdentityLabel: session.displayName
    )
}

@MainActor
private func makeSharedRoll(id: UUID, creatorID: UUID, status: V2Domain.RollStatus) -> LocalRoll {
    LocalRoll(
        id: id,
        title: "Shared Roll",
        type: .shared,
        status: status,
        film_stock_id: FilmStock.kodakGold200.rawValue,
        exposures_per_participant: 12,
        creator_id: creatorID,
        created_at: .now
    )
}

@MainActor
private func makeParticipant(id: UUID, rollID: UUID, userID: UUID, name: String) -> LocalParticipant {
    LocalParticipant(
        id: id,
        roll_id: rollID,
        user_id: userID,
        display_name: name,
        status: .joined,
        joined_at: .now
    )
}

@MainActor
private func makeExposure(id: UUID, rollID: UUID, participantID: UUID, exposureNumber: Int) -> LocalExposure {
    LocalExposure(
        id: id,
        roll_id: rollID,
        participant_id: participantID,
        exposure_number: exposureNumber,
        render_seed: "seed-\(exposureNumber)",
        sync_state: .empty,
        updated_at: .now
    )
}

private actor SharedLobbyAuthRepository: AuthRepository {
    private let session: AuthSession

    init(session: AuthSession) {
        self.session = session
    }

    func currentSession() async throws -> AuthSession? {
        session
    }

    func currentUserID() async throws -> UUID? {
        await MainActor.run { session.userID }
    }

    func signOut() async throws {}
}

private actor SharedLobbyRollRepository: RollRepository {
    private var currentRoll: RollSnapshot
    private let startedRoll: RollSnapshot?
    private(set) var startedRollIDs: [UUID] = []

    init(roll: LocalRoll, startedRoll: LocalRoll? = nil) {
        self.currentRoll = RollSnapshot(roll)
        self.startedRoll = startedRoll.map(RollSnapshot.init)
    }

    func fetchRoll(id: UUID) async throws -> LocalRoll? {
        guard currentRoll.id == id else {
            return nil
        }

        let snapshot = currentRoll

        return await MainActor.run {
            snapshot.makeLocalRoll()
        }
    }

    func fetchRolls() async throws -> [LocalRoll] {
        let snapshot = currentRoll
        return await MainActor.run { [snapshot.makeLocalRoll()] }
    }

    func fetchAllRolls() async throws -> [LocalRoll] {
        try await fetchRolls()
    }

    func startRoll(id: UUID) async throws {
        startedRollIDs.append(id)
        if let startedRoll {
            currentRoll = startedRoll
        } else {
            currentRoll.status = .shooting
        }
    }

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

private actor SharedLobbyParticipantRepository: ParticipantRepository {
    private var participants: [ParticipantSnapshot]
    private let removeError: Error?
    private(set) var leftRollIDs: [UUID] = []
    private(set) var removedParticipantIDs: [UUID] = []

    init(participants: [LocalParticipant], removeError: Error? = nil) {
        self.participants = participants.map(ParticipantSnapshot.init)
        self.removeError = removeError
    }

    func fetchParticipants(forRollID rollID: UUID) async throws -> [LocalParticipant] {
        let matching = participants.filter { $0.rollID == rollID }
        return await MainActor.run {
            matching.map { $0.makeLocalParticipant() }
        }
    }

    func fetchParticipant(id: UUID) async throws -> LocalParticipant? {
        guard let participant = participants.first(where: { $0.id == id }) else {
            return nil
        }

        return await MainActor.run {
            participant.makeLocalParticipant()
        }
    }

    func joinRoll(inviteToken: String) async throws -> JoinRollResult {
        JoinRollResult(rollID: UUID(), participantID: UUID())
    }

    func leaveRoll(rollID: UUID) async throws {
        leftRollIDs.append(rollID)
    }

    func saveParticipant(_ participant: LocalParticipant) async throws {}

    func deleteParticipant(id: UUID) async throws {
        if let removeError {
            throw removeError
        }

        removedParticipantIDs.append(id)
        participants.removeAll { $0.id == id }
    }
}

private actor SharedLobbyInviteRepository: InviteRepository {
    private var currentInvite: InviteSnapshot?
    private let regeneratedInviteValue: InviteSnapshot?
    private(set) var regeneratedRollIDs: [UUID] = []

    init(invite: LocalInvite? = nil, regeneratedInvite: LocalInvite? = nil) {
        self.currentInvite = invite.map(InviteSnapshot.init)
        self.regeneratedInviteValue = regeneratedInvite.map(InviteSnapshot.init)
    }

    func fetchInvite(forRollID rollID: UUID) async throws -> LocalInvite? {
        guard let currentInvite, currentInvite.rollID == rollID else {
            return nil
        }

        return await MainActor.run {
            currentInvite.makeLocalInvite()
        }
    }

    func fetchInvite(token: String) async throws -> LocalInvite? {
        guard let currentInvite, currentInvite.token == token else {
            return nil
        }

        return await MainActor.run {
            currentInvite.makeLocalInvite()
        }
    }

    func regenerateInvite(forRollID rollID: UUID) async throws -> LocalInvite {
        regeneratedRollIDs.append(rollID)
        if let regeneratedInviteValue {
            currentInvite = regeneratedInviteValue
        }

        guard let currentInvite else {
            throw V2RepositoryError.notFound("Invite not found.")
        }

        return await MainActor.run {
            currentInvite.makeLocalInvite()
        }
    }

    func saveInvite(_ invite: LocalInvite) async throws {}
    func deleteInvite(id: UUID) async throws {}
}

private actor SharedLobbyExposureRepository: ExposureRepository {
    private let exposuresByParticipantID: [UUID: [ExposureSnapshot]]
    private(set) var fetchedParticipantIDs: [UUID] = []

    init(exposuresByParticipantID: [UUID: [LocalExposure]] = [:]) {
        self.exposuresByParticipantID = exposuresByParticipantID.mapValues { exposures in
            exposures.map(ExposureSnapshot.init)
        }
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] { [] }

    func fetchExposures(forParticipantID participantID: UUID) async throws -> [LocalExposure] {
        fetchedParticipantIDs.append(participantID)
        let exposures = exposuresByParticipantID[participantID] ?? []
        return await MainActor.run {
            exposures.map { $0.makeLocalExposure() }
        }
    }

    func fetchExposure(id: UUID) async throws -> LocalExposure? { nil }
    func completeExposure(id: UUID, storagePath: String) async throws -> CompleteExposureResult {
        CompleteExposureResult(participantFinished: false, rollReadyToReveal: false)
    }
    func saveExposure(_ exposure: LocalExposure) async throws {}
    func saveExposures(_ exposures: [LocalExposure]) async throws {}
}

@MainActor
private final class SharedLobbyMirrorStore: ExposureMirrorStore {
    private var exposuresByRollID: [UUID: [LocalExposure]] = [:]

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] ?? []
    }

    func mirrorCloudExposures(_ exposures: [LocalExposure], forRollID rollID: UUID) async throws -> [LocalExposure] {
        exposuresByRollID[rollID] = exposures
        return exposures
    }

    func saveExposure(_ exposure: LocalExposure) async throws {
        var exposures = exposuresByRollID[exposure.roll_id] ?? []
        exposures.removeAll { $0.id == exposure.id }
        exposures.append(exposure)
        exposuresByRollID[exposure.roll_id] = exposures
    }
}

private struct RollSnapshot {
    let id: UUID
    let title: String
    var status: V2Domain.RollStatus
    let filmStockID: String
    let exposuresPerParticipant: Int
    let creatorID: UUID
    let createdAt: Date

    init(_ roll: LocalRoll) {
        self.id = roll.id
        self.title = roll.title
        self.status = roll.status
        self.filmStockID = roll.film_stock_id
        self.exposuresPerParticipant = roll.exposures_per_participant
        self.creatorID = roll.creator_id
        self.createdAt = roll.created_at
    }

    func makeLocalRoll() -> LocalRoll {
        LocalRoll(
            id: id,
            title: title,
            type: .shared,
            status: status,
            film_stock_id: filmStockID,
            exposures_per_participant: exposuresPerParticipant,
            creator_id: creatorID,
            created_at: createdAt
        )
    }
}

private struct ParticipantSnapshot {
    let id: UUID
    let rollID: UUID
    let userID: UUID
    let displayName: String?
    let status: V2Domain.ParticipantStatus
    let joinedAt: Date

    init(_ participant: LocalParticipant) {
        self.id = participant.id
        self.rollID = participant.roll_id
        self.userID = participant.user_id
        self.displayName = participant.display_name
        self.status = participant.status
        self.joinedAt = participant.joined_at
    }

    func makeLocalParticipant() -> LocalParticipant {
        LocalParticipant(
            id: id,
            roll_id: rollID,
            user_id: userID,
            display_name: displayName,
            status: status,
            joined_at: joinedAt
        )
    }
}

private struct InviteSnapshot {
    let id: UUID
    let rollID: UUID
    let token: String
    let isActive: Bool
    let createdAt: Date

    init(_ invite: LocalInvite) {
        self.id = invite.id
        self.rollID = invite.roll_id
        self.token = invite.token
        self.isActive = invite.is_active
        self.createdAt = invite.created_at
    }

    func makeLocalInvite() -> LocalInvite {
        LocalInvite(
            id: id,
            roll_id: rollID,
            token: token,
            is_active: isActive,
            created_at: createdAt
        )
    }
}

private struct ExposureSnapshot {
    let id: UUID
    let rollID: UUID
    let participantID: UUID
    let exposureNumber: Int
    let renderSeed: String
    let syncState: V2Domain.ExposureSyncState
    let updatedAt: Date

    init(_ exposure: LocalExposure) {
        self.id = exposure.id
        self.rollID = exposure.roll_id
        self.participantID = exposure.participant_id
        self.exposureNumber = exposure.exposure_number
        self.renderSeed = exposure.render_seed
        self.syncState = exposure.sync_state
        self.updatedAt = exposure.updated_at
    }

    func makeLocalExposure() -> LocalExposure {
        LocalExposure(
            id: id,
            roll_id: rollID,
            participant_id: participantID,
            exposure_number: exposureNumber,
            render_seed: renderSeed,
            sync_state: syncState,
            updated_at: updatedAt
        )
    }
}
