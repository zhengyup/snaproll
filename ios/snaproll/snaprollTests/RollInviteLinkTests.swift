import Foundation
import Testing
@testable import snaproll

struct RollInviteLinkTests {
    @Test
    func validTokenGeneratesDevelopmentURL() throws {
        let invite = try #require(RollInviteLink(token: "ABC123"))

        #expect(invite.url.absoluteString == "snaproll://join?token=ABC123")
    }

    @Test
    func tokenIsEncodedSafely() throws {
        let invite = try #require(RollInviteLink(token: "abc 123/+="))

        #expect(!invite.url.absoluteString.contains(" "))
        #expect(RollInviteLink.parse(invite.url)?.token == "abc 123/+=")
    }

    @Test
    func httpsPathTokenIsEncodedSafely() throws {
        let invite = try #require(RollInviteLink(token: "abc 123/+="))
        let url = invite.url(httpsDomain: "links.snaproll.test")
        let encodedPath = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath)

        #expect(!encodedPath.contains(" "))
        #expect(encodedPath.split(separator: "/").count == 2)
        #expect(RollInviteLink.parse(url, httpsDomain: "links.snaproll.test")?.token == "abc 123/+=")
    }

    @Test
    func emptyTokenIsRejected() {
        #expect(RollInviteLink(token: "   ") == nil)
    }

    @Test
    func parsesValidCustomSchemeQueryToken() throws {
        let url = try #require(URL(string: "snaproll://join?token=TOKEN-1"))

        #expect(RollInviteLink.parse(url)?.token == "TOKEN-1")
    }

    @Test
    func parsesValidHTTPSPathToken() throws {
        let url = try #require(URL(string: "https://links.snaproll.test/join/TOKEN-2"))

        #expect(RollInviteLink.parse(url, httpsDomain: "links.snaproll.test")?.token == "TOKEN-2")
    }

    @Test
    func parsesValidHTTPSQueryToken() throws {
        let url = try #require(URL(string: "https://links.snaproll.test/join?token=TOKEN-3"))

        #expect(RollInviteLink.parse(url, httpsDomain: "links.snaproll.test")?.token == "TOKEN-3")
    }

    @Test
    func rejectsUnrelatedDomain() throws {
        let url = try #require(URL(string: "https://example.com/join/TOKEN"))

        #expect(RollInviteLink.parse(url, httpsDomain: "links.snaproll.test") == nil)
    }

    @Test
    func rejectsUnrelatedPath() throws {
        let url = try #require(URL(string: "snaproll://rolls?token=TOKEN"))

        #expect(RollInviteLink.parse(url) == nil)
    }

    @Test
    func rejectsMissingToken() throws {
        let url = try #require(URL(string: "snaproll://join"))

        #expect(RollInviteLink.parse(url) == nil)
    }

    @Test
    func rejectsEmptyToken() throws {
        let url = try #require(URL(string: "snaproll://join?token=%20%20"))

        #expect(RollInviteLink.parse(url) == nil)
    }
}
