import Combine
import Foundation

enum V2RollInvitePreviewState: Equatable {
    case idle
    case loading
    case loaded(RollInvitePreview)
    case failed(String)
}

@MainActor
final class V2RollInvitePreviewViewModel: ObservableObject {
    @Published private(set) var state: V2RollInvitePreviewState = .idle
    @Published private(set) var isJoining = false
    @Published private(set) var joinErrorMessage: String?

    private let invite: RollInviteLink
    private let invitePreviewRepository: any InvitePreviewRepository
    private let participantRepository: any ParticipantRepository
    private var hasLoaded = false

    init(
        invite: RollInviteLink,
        invitePreviewRepository: any InvitePreviewRepository,
        participantRepository: any ParticipantRepository
    ) {
        self.invite = invite
        self.invitePreviewRepository = invitePreviewRepository
        self.participantRepository = participantRepository
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await load()
    }

    func retry() async {
        hasLoaded = true
        await load()
    }

    func join() async -> UUID? {
        guard !isJoining else {
            return nil
        }

        isJoining = true
        defer { isJoining = false }
        joinErrorMessage = nil

        do {
            let result = try await participantRepository.joinRoll(inviteToken: invite.token)
            return result.rollID
        } catch {
            if case .loaded(let preview) = state,
               isAlreadyParticipantError(error) {
                return preview.rollID
            }

            joinErrorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    private func load() async {
        state = .loading
        joinErrorMessage = nil

        do {
            let preview = try await invitePreviewRepository.fetchInvitePreview(token: invite.token)
            guard preview.isActive else {
                state = .failed("This invite link is no longer active. Ask the creator for a new one.")
                return
            }

            state = .loaded(preview)
        } catch {
            state = .failed(userFacingMessage(for: error))
        }
    }

    private func isAlreadyParticipantError(_ error: Error) -> Bool {
        guard case .conflict(let message) = error as? V2RepositoryError else {
            return false
        }

        return message.localizedCaseInsensitiveContains("already")
    }

    private func userFacingMessage(for error: Error) -> String {
        guard let repositoryError = error as? V2RepositoryError else {
            return "Couldn’t load this invitation. Check your connection and try again."
        }

        switch repositoryError {
        case .notFound:
            return "This invite link is no longer active. Ask the creator for a new one."
        case .invalidInput:
            return "This Snaproll invite link is not valid."
        case .lifecycleViolation:
            return "This roll is no longer accepting participants."
        case .businessRuleViolation(let message):
            if message.localizedCaseInsensitiveContains("inactive")
                || message.localizedCaseInsensitiveContains("invalid") {
                return "This invite link is no longer active. Ask the creator for a new one."
            }

            if message.localizedCaseInsensitiveContains("started")
                || message.localizedCaseInsensitiveContains("accept")
                || message.localizedCaseInsensitiveContains("cap") {
                return "This roll is no longer accepting participants."
            }

            return message
        case .network:
            return "Couldn’t load this invitation. Check your connection and try again."
        case .authenticationRequired:
            return "Sign in to view this invitation."
        default:
            return "Couldn’t load this invitation. Check your connection and try again."
        }
    }
}
