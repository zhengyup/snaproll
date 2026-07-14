import Combine
import Foundation

struct V2JoinedInviteRoute: Identifiable, Equatable, Hashable {
    let rollID: UUID

    var id: UUID { rollID }
}

@MainActor
final class V2InviteRoutingCoordinator: ObservableObject {
    @Published private(set) var pendingInvite: RollInviteLink?
    @Published var joinedRoute: V2JoinedInviteRoute?
    @Published private(set) var invalidInviteMessage: String?

    func handleIncomingURL(_ url: URL) {
        guard let invite = RollInviteLink.parse(url) else {
            invalidInviteMessage = "This Snaproll invite link is not valid."
            return
        }

        invalidInviteMessage = nil
        joinedRoute = nil
        pendingInvite = invite
    }

    func dismissPendingInvite() {
        pendingInvite = nil
    }

    func completeJoin(rollID: UUID) {
        pendingInvite = nil
        invalidInviteMessage = nil
        joinedRoute = V2JoinedInviteRoute(rollID: rollID)
    }

    func dismissInvalidInviteMessage() {
        invalidInviteMessage = nil
    }
}
