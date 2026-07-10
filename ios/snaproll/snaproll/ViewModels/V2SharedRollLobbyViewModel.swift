import Combine
import Foundation

enum V2SharedRollLobbyState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class V2SharedRollLobbyViewModel: ObservableObject {
    @Published private(set) var state: V2SharedRollLobbyState = .idle
    @Published private(set) var roll: LocalRoll?
    @Published private(set) var currentSession: AuthSession?
    @Published private(set) var participants: [LocalParticipant] = []
    @Published private(set) var invite: LocalInvite?

    let rollID: UUID

    private let authRepository: any AuthRepository
    private let rollRepository: any RollRepository
    private let participantRepository: any ParticipantRepository
    private let inviteRepository: any InviteRepository
    private let activeDevelopmentIdentityLabel: String?

    init(
        rollID: UUID,
        authRepository: any AuthRepository,
        rollRepository: any RollRepository,
        participantRepository: any ParticipantRepository,
        inviteRepository: any InviteRepository,
        activeDevelopmentIdentityLabel: String? = nil
    ) {
        self.rollID = rollID
        self.authRepository = authRepository
        self.rollRepository = rollRepository
        self.participantRepository = participantRepository
        self.inviteRepository = inviteRepository
        self.activeDevelopmentIdentityLabel = activeDevelopmentIdentityLabel
    }

    var title: String {
        roll?.title ?? "Shared Roll"
    }

    var statusLabel: String {
        roll?.status.rawValue.replacingOccurrences(of: "_", with: " ") ?? "Loading"
    }

    var activeIdentityLabel: String? {
        activeDevelopmentIdentityLabel
    }

    var currentUserID: UUID? {
        currentSession?.userID
    }

    var isCreator: Bool {
        guard let roll, let currentUserID else {
            return false
        }

        return roll.creator_id == currentUserID
    }

    var participantCountLabel: String {
        "\(participants.count) participant\(participants.count == 1 ? "" : "s")"
    }

    var visibleInviteToken: String? {
        isCreator ? invite?.token : nil
    }

    func load() async {
        state = .loading

        do {
            try await reload()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        await load()
    }

    private func reload() async throws {
        async let sessionTask = authRepository.currentSession()
        async let rollTask = rollRepository.fetchRoll(id: rollID)
        async let participantsTask = participantRepository.fetchParticipants(forRollID: rollID)

        let fetchedSession = try await sessionTask
        guard let fetchedRoll = try await rollTask else {
            throw V2RepositoryError.notFound("The shared roll could not be found.")
        }

        currentSession = fetchedSession
        roll = fetchedRoll
        participants = try await participantsTask

        if isCreator {
            invite = try await inviteRepository.fetchInvite(forRollID: rollID)
        } else {
            invite = nil
        }
    }
}
