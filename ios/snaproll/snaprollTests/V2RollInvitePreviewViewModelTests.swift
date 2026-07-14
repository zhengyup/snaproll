import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2RollInvitePreviewViewModelTests {
    @Test
    func successfulJoinRoutesToLobby() async throws {
        let rollID = UUID()
        let participantRepository = InvitePreviewParticipantRepository(
            joinResults: [.success(JoinRollResult(rollID: rollID, participantID: UUID()))]
        )
        let viewModel = makeInvitePreviewViewModel(
            token: "JOIN",
            previewRepository: InvitePreviewRepositoryFake(previews: ["JOIN": makePreview(rollID: rollID)]),
            participantRepository: participantRepository
        )

        await viewModel.loadIfNeeded()
        let joinedRollID = await viewModel.join()

        #expect(joinedRollID == rollID)
        #expect(await participantRepository.joinCallCount == 1)
    }

    @Test
    func repeatedJoinTapIsPrevented() async throws {
        let rollID = UUID()
        let participantRepository = InvitePreviewParticipantRepository(
            joinResults: [.success(JoinRollResult(rollID: rollID, participantID: UUID()))],
            delayNanoseconds: 100_000_000
        )
        let viewModel = makeInvitePreviewViewModel(
            token: "JOIN",
            previewRepository: InvitePreviewRepositoryFake(previews: ["JOIN": makePreview(rollID: rollID)]),
            participantRepository: participantRepository
        )

        await viewModel.loadIfNeeded()
        async let first: UUID? = viewModel.join()
        async let second: UUID? = viewModel.join()
        _ = await (first, second)

        #expect(await participantRepository.joinCallCount == 1)
    }

    @Test
    func alreadyParticipantRoutesToExistingRoll() async throws {
        let rollID = UUID()
        let participantRepository = InvitePreviewParticipantRepository(
            joinResults: [.failure(V2RepositoryError.conflict("You are already a participant in this roll."))]
        )
        let viewModel = makeInvitePreviewViewModel(
            token: "JOIN",
            previewRepository: InvitePreviewRepositoryFake(previews: ["JOIN": makePreview(rollID: rollID)]),
            participantRepository: participantRepository
        )

        await viewModel.loadIfNeeded()
        let joinedRollID = await viewModel.join()

        #expect(joinedRollID == rollID)
        #expect(viewModel.joinErrorMessage == nil)
    }

    @Test
    func invalidInviteProducesMappedError() async throws {
        let viewModel = makeInvitePreviewViewModel(
            token: "BAD",
            previewRepository: InvitePreviewRepositoryFake(error: V2RepositoryError.invalidInput("invite_token is required.")),
            participantRepository: InvitePreviewParticipantRepository()
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.state == .failed("This Snaproll invite link is not valid."))
    }

    @Test
    func networkFailureRemainsRetryable() async throws {
        let viewModel = makeInvitePreviewViewModel(
            token: "JOIN",
            previewRepository: InvitePreviewRepositoryFake(error: V2RepositoryError.network("offline")),
            participantRepository: InvitePreviewParticipantRepository()
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.state == .failed("Couldn’t load this invitation. Check your connection and try again."))
    }
}

@MainActor
private func makeInvitePreviewViewModel(
    token: String,
    previewRepository: InvitePreviewRepositoryFake,
    participantRepository: InvitePreviewParticipantRepository
) -> V2RollInvitePreviewViewModel {
    V2RollInvitePreviewViewModel(
        invite: RollInviteLink(token: token)!,
        invitePreviewRepository: previewRepository,
        participantRepository: participantRepository
    )
}

private func makePreview(rollID: UUID) -> RollInvitePreview {
    RollInvitePreview(
        rollID: rollID,
        title: "Shared Roll",
        creatorDisplayName: "Creator",
        participantCount: 1,
        participantCap: 10,
        exposuresPerParticipant: 3,
        status: .waitingForParticipants,
        isActive: true,
        isAcceptingParticipants: true
    )
}

private struct InvitePreviewRepositoryFake: InvitePreviewRepository {
    let previews: [String: RollInvitePreview]
    let error: Error?

    init(previews: [String: RollInvitePreview] = [:], error: Error? = nil) {
        self.previews = previews
        self.error = error
    }

    func fetchInvitePreview(token: String) async throws -> RollInvitePreview {
        if let error {
            throw error
        }

        guard let preview = previews[token] else {
            throw V2RepositoryError.notFound("Invite not found.")
        }

        return preview
    }
}

private actor InvitePreviewParticipantRepository: ParticipantRepository {
    private var joinResults: [Result<JoinRollResult, Error>]
    private let delayNanoseconds: UInt64
    private(set) var joinCallCount = 0

    init(
        joinResults: [Result<JoinRollResult, Error>] = [],
        delayNanoseconds: UInt64 = 0
    ) {
        self.joinResults = joinResults
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchParticipants(forRollID rollID: UUID) async throws -> [LocalParticipant] { [] }
    func fetchParticipant(id: UUID) async throws -> LocalParticipant? { nil }

    func joinRoll(inviteToken: String) async throws -> JoinRollResult {
        joinCallCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        if !joinResults.isEmpty {
            return try joinResults.removeFirst().get()
        }

        return JoinRollResult(rollID: UUID(), participantID: UUID())
    }

    func leaveRoll(rollID: UUID) async throws {}
    func saveParticipant(_ participant: LocalParticipant) async throws {}
    func deleteParticipant(id: UUID) async throws {}
}
