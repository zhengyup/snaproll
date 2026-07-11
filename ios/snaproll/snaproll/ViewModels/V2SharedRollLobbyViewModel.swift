import Combine
import Foundation

enum V2SharedRollLobbyState: Equatable {
    case idle
    case loading
    case loaded
    case left
    case failed(String)
}

@MainActor
final class V2SharedRollLobbyViewModel: ObservableObject {
    struct DiagnosticsSummary: Equatable {
        let rollID: UUID
        let creatorID: UUID
        let participantCount: Int
        let mirroredExposureCount: Int
        let rollStatus: V2Domain.RollStatus
        let currentParticipantID: UUID?
        let participantIDs: [UUID]
    }

    @Published private(set) var state: V2SharedRollLobbyState = .idle
    @Published private(set) var roll: LocalRoll?
    @Published private(set) var currentSession: AuthSession?
    @Published private(set) var participants: [LocalParticipant] = []
    @Published private(set) var invite: LocalInvite?
    @Published private(set) var mirroredExposures: [LocalExposure] = []
    @Published private(set) var isStartingRoll = false
    @Published private(set) var isRegeneratingInvite = false
    @Published private(set) var isLeavingRoll = false
    @Published private(set) var activeRemovalParticipantID: UUID?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var actionStatusMessage: String?

    let rollID: UUID

    private let authRepository: any AuthRepository
    private let rollRepository: any RollRepository
    private let participantRepository: any ParticipantRepository
    private let inviteRepository: any InviteRepository
    private let exposureRepository: any ExposureRepository
    private let exposureMirrorStore: any ExposureMirrorStore
    private let diagnosticsEnabled: Bool
    private let activeDevelopmentIdentityLabel: String?

    init(
        rollID: UUID,
        authRepository: any AuthRepository,
        rollRepository: any RollRepository,
        participantRepository: any ParticipantRepository,
        inviteRepository: any InviteRepository,
        exposureRepository: any ExposureRepository,
        exposureMirrorStore: any ExposureMirrorStore,
        diagnosticsEnabled: Bool? = nil,
        activeDevelopmentIdentityLabel: String? = nil
    ) {
        self.rollID = rollID
        self.authRepository = authRepository
        self.rollRepository = rollRepository
        self.participantRepository = participantRepository
        self.inviteRepository = inviteRepository
        self.exposureRepository = exposureRepository
        self.exposureMirrorStore = exposureMirrorStore
        self.diagnosticsEnabled = diagnosticsEnabled ?? AppConfig.V2.isExposureDiagnosticsEnabled
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

    var currentParticipant: LocalParticipant? {
        guard let currentUserID else {
            return nil
        }

        return participants.first(where: { $0.user_id == currentUserID })
    }

    var isCreator: Bool {
        guard let roll, let currentUserID else {
            return false
        }

        return roll.creator_id == currentUserID
    }

    var isMutableLobby: Bool {
        roll?.status == .waitingForParticipants
    }

    var canStartRoll: Bool {
        isCreator && isMutableLobby
    }

    var canRegenerateInvite: Bool {
        isCreator && isMutableLobby
    }

    var canLeaveRoll: Bool {
        !isCreator && isMutableLobby && currentParticipant != nil
    }

    var participantCountLabel: String {
        "\(participants.count) participant\(participants.count == 1 ? "" : "s")"
    }

    var visibleInviteToken: String? {
        isCreator ? invite?.token : nil
    }

    var shouldShowDiagnostics: Bool {
        diagnosticsEnabled
    }

    var mirroredExposureCount: Int {
        mirroredExposures.count
    }

    var diagnosticsSummary: DiagnosticsSummary? {
        guard diagnosticsEnabled, let roll else {
            return nil
        }

        return DiagnosticsSummary(
            rollID: roll.id,
            creatorID: roll.creator_id,
            participantCount: participants.count,
            mirroredExposureCount: mirroredExposureCount,
            rollStatus: roll.status,
            currentParticipantID: currentParticipant?.id,
            participantIDs: participants.map(\.id)
        )
    }

    func canRemoveParticipant(_ participant: LocalParticipant) -> Bool {
        isCreator && isMutableLobby && participant.user_id != currentUserID
    }

    func load() async {
        state = .loading
        actionErrorMessage = nil

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

    func leaveRoll() async {
        guard canLeaveRoll else {
            actionErrorMessage = isCreator
                ? "The creator cannot leave their own roll."
                : "You can only leave before the roll starts."
            actionStatusMessage = nil
            return
        }

        isLeavingRoll = true
        defer { isLeavingRoll = false }
        actionErrorMessage = nil
        actionStatusMessage = nil

        do {
            try await participantRepository.leaveRoll(rollID: rollID)
            participants = []
            mirroredExposures = []
            invite = nil
            actionStatusMessage = "You left the roll."
            state = .left
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func removeParticipant(id participantID: UUID) async {
        guard let participant = participants.first(where: { $0.id == participantID }) else {
            actionErrorMessage = "Participant not found."
            actionStatusMessage = nil
            return
        }

        guard canRemoveParticipant(participant) else {
            actionErrorMessage = "This participant can no longer be removed."
            actionStatusMessage = nil
            return
        }

        activeRemovalParticipantID = participantID
        defer { activeRemovalParticipantID = nil }
        actionErrorMessage = nil
        actionStatusMessage = nil

        do {
            try await participantRepository.deleteParticipant(id: participantID)
            actionStatusMessage = "Participant removed."
            try await reload()
            state = .loaded
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func regenerateInvite() async {
        guard canRegenerateInvite else {
            actionErrorMessage = "Invite changes are only available before the roll starts."
            actionStatusMessage = nil
            return
        }

        isRegeneratingInvite = true
        defer { isRegeneratingInvite = false }
        actionErrorMessage = nil
        actionStatusMessage = nil

        do {
            invite = try await inviteRepository.regenerateInvite(forRollID: rollID)
            actionStatusMessage = "Invite regenerated."
            try await reload()
            state = .loaded
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func startRoll() async {
        guard canStartRoll else {
            actionErrorMessage = "Only the creator can start the roll while the lobby is still open."
            actionStatusMessage = nil
            return
        }

        isStartingRoll = true
        defer { isStartingRoll = false }
        actionErrorMessage = nil
        actionStatusMessage = nil

        do {
            try await rollRepository.startRoll(id: rollID)
            try await reload()
            actionStatusMessage = mirroredExposureCount > 0
                ? "Roll started. Exposure plan mirrored locally."
                : "Roll started."
            state = .loaded
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func reload() async throws {
        async let sessionTask = authRepository.currentSession()
        async let rollTask = rollRepository.fetchRoll(id: rollID)
        async let participantsTask = participantRepository.fetchParticipants(forRollID: rollID)

        let fetchedSession = try await sessionTask
        guard let fetchedRoll = try await rollTask else {
            throw V2RepositoryError.notFound("The shared roll could not be found.")
        }

        let fetchedParticipants = try await participantsTask

        currentSession = fetchedSession
        roll = fetchedRoll
        participants = fetchedParticipants.sorted(by: { $0.joined_at < $1.joined_at })

        if isCreator {
            invite = try await inviteRepository.fetchInvite(forRollID: rollID)
        } else {
            invite = nil
        }

        if fetchedRoll.status == .shooting || fetchedRoll.status == .readyToReveal || fetchedRoll.status == .revealed,
           let participant = currentParticipant {
            let cloudExposures = try await exposureRepository.fetchExposures(forParticipantID: participant.id)
            mirroredExposures = try await exposureMirrorStore
                .mirrorCloudExposures(cloudExposures, forRollID: rollID)
                .sorted(by: { $0.exposure_number < $1.exposure_number })
        } else {
            mirroredExposures = []
        }
    }
}
