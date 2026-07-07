import Foundation
import Testing
@testable import snaproll

struct DevelopmentAuthTests {
    @Test
    func developmentAuthReturnsSelectedCreatorIdentity() async throws {
        let client = FakeDevelopmentAuthClient(nextUserID: FakeDevelopmentAuthClient.creatorUserID)
        let resolver = DevelopmentAuthSessionResolver(
            identityProvider: FixedDevelopmentAuthIdentityProvider(identity: .creator),
            sessionStore: InMemoryDevelopmentAuthSessionStore(),
            client: client
        )

        let session = try await resolver.resolveSession()

        #expect(session.userID == FakeDevelopmentAuthClient.creatorUserID)
        #expect(session.displayName == DevelopmentAuthIdentity.creator.displayName)
    }

    @Test
    func developmentAuthReturnsSelectedParticipantAIdentity() async throws {
        let client = FakeDevelopmentAuthClient(nextUserID: FakeDevelopmentAuthClient.participantAUserID)
        let resolver = DevelopmentAuthSessionResolver(
            identityProvider: FixedDevelopmentAuthIdentityProvider(identity: .participantA),
            sessionStore: InMemoryDevelopmentAuthSessionStore(),
            client: client
        )

        let session = try await resolver.resolveSession()

        #expect(session.userID == FakeDevelopmentAuthClient.participantAUserID)
        #expect(session.displayName == DevelopmentAuthIdentity.participantA.displayName)
    }

    @Test
    func flagsDisabledResolveToStandardAuthenticationMode() {
        let mode = resolvedAuthenticationMode(
            isDevelopmentAuthenticationEnabled: false,
            selectedIdentity: .participantB
        )

        #expect(mode == .standard)
    }
}

@MainActor
struct V2SessionStoreSignOutTests {
    @Test
    func developmentAuthSignOutTransitionsToSignedOut() async {
        let store = V2SessionStore(
            bootstrapper: V2SessionBootstrapper(
                authRepository: FakeSignOutAuthRepository()
            )
        )

        await store.signOut()

        #expect(store.state == .signedOut)
    }
}

private final class InMemoryDevelopmentAuthSessionStore: DevelopmentAuthSessionPersisting, @unchecked Sendable {
    private var storage: [DevelopmentAuthIdentity: PersistedDevelopmentAuthSession] = [:]

    func loadSession(for identity: DevelopmentAuthIdentity) -> PersistedDevelopmentAuthSession? {
        storage[identity]
    }

    func saveSession(_ session: PersistedDevelopmentAuthSession, for identity: DevelopmentAuthIdentity) {
        storage[identity] = session
    }
}

private struct FakeDevelopmentAuthClient: DevelopmentAuthClient {
    static let creatorUserID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let participantAUserID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let participantBUserID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let nextUserID: UUID

    func restoreSession(accessToken: String, refreshToken: String) async throws -> DevelopmentAuthResolvedSession {
        throw FakeDevelopmentAuthError.notImplemented
    }

    func signInAnonymously() async throws -> DevelopmentAuthResolvedSession {
        DevelopmentAuthResolvedSession(
            userID: nextUserID,
            accessToken: "access-\(nextUserID.uuidString)",
            refreshToken: "refresh-\(nextUserID.uuidString)"
        )
    }

    func ensureProfile(displayName: String) async throws -> String? {
        displayName
    }

    func signOut() async throws {}
}

private struct FakeSignOutAuthRepository: AuthRepository {
    func currentSession() async throws -> AuthSession? { nil }
    func currentUserID() async throws -> UUID? { nil }
    func signOut() async throws {}
}

private enum FakeDevelopmentAuthError: Error {
    case notImplemented
}

private func resolvedAuthenticationMode(
    isDevelopmentAuthenticationEnabled: Bool,
    selectedIdentity: DevelopmentAuthIdentity
) -> V2AuthenticationMode {
    if isDevelopmentAuthenticationEnabled {
        return .development(selectedIdentity)
    }

    return .standard
}
