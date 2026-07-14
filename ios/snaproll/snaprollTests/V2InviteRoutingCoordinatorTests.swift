import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2InviteRoutingCoordinatorTests {
    @Test
    func inviteOpenedWhileSignedOutIsRetained() throws {
        let coordinator = V2InviteRoutingCoordinator()
        let url = try #require(URL(string: "snaproll://join?token=PENDING"))

        coordinator.handleIncomingURL(url)

        #expect(coordinator.pendingInvite?.token == "PENDING")
    }

    @Test
    func inviteIsClearedAfterDismissal() throws {
        let coordinator = V2InviteRoutingCoordinator()
        let url = try #require(URL(string: "snaproll://join?token=PENDING"))

        coordinator.handleIncomingURL(url)
        coordinator.dismissPendingInvite()

        #expect(coordinator.pendingInvite == nil)
    }

    @Test
    func inviteIsClearedAfterSuccessfulJoin() throws {
        let coordinator = V2InviteRoutingCoordinator()
        let rollID = UUID()
        let url = try #require(URL(string: "snaproll://join?token=PENDING"))

        coordinator.handleIncomingURL(url)
        coordinator.completeJoin(rollID: rollID)

        #expect(coordinator.pendingInvite == nil)
        #expect(coordinator.joinedRoute?.rollID == rollID)
    }

    @Test
    func secondValidLinkReplacesPendingInvite() throws {
        let coordinator = V2InviteRoutingCoordinator()
        let firstURL = try #require(URL(string: "snaproll://join?token=FIRST"))
        let secondURL = try #require(URL(string: "snaproll://join?token=SECOND"))

        coordinator.handleIncomingURL(firstURL)
        coordinator.handleIncomingURL(secondURL)

        #expect(coordinator.pendingInvite?.token == "SECOND")
    }

    @Test
    func malformedInviteProducesInvalidMessageWithoutPendingInvite() throws {
        let coordinator = V2InviteRoutingCoordinator()
        let url = try #require(URL(string: "snaproll://other?token=BAD"))

        coordinator.handleIncomingURL(url)

        #expect(coordinator.pendingInvite == nil)
        #expect(coordinator.invalidInviteMessage == "This Snaproll invite link is not valid.")
    }
}
