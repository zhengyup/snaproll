import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2SessionBootstrapTests {
    @Test
    func storeStartsInLoadingState() {
        let store = V2SessionStore(
            bootstrapper: V2SessionBootstrapper(
                authRepository: FakeAuthRepository(result: .success(nil))
            )
        )

        #expect(store.state == .loading)
    }

    @Test
    func noExistingSessionTransitionsToSignedOut() async {
        let store = V2SessionStore(
            bootstrapper: V2SessionBootstrapper(
                authRepository: FakeAuthRepository(result: .success(nil))
            )
        )

        await store.bootstrapIfNeeded()

        #expect(store.state == .signedOut)
    }

    @Test
    func existingSessionLoadsSuccessfullyTransitionsToSignedIn() async {
        let session = AuthSession(
            userID: UUID(),
            displayName: "Zheng"
        )
        let store = V2SessionStore(
            bootstrapper: V2SessionBootstrapper(
                authRepository: FakeAuthRepository(result: .success(session))
            )
        )

        await store.bootstrapIfNeeded()

        #expect(store.state == .signedIn(session))
    }

    @Test
    func existingSessionProfileFetchFailureTransitionsToFailed() async {
        let store = V2SessionStore(
            bootstrapper: V2SessionBootstrapper(
                authRepository: FakeAuthRepository(
                    result: .failure(FakeBootstrapError.profileFetchFailed)
                )
            )
        )

        await store.bootstrapIfNeeded()

        guard case .failed(let message) = store.state else {
            Issue.record("Expected failed state but got \(store.state)")
            return
        }

        #expect(message == FakeBootstrapError.profileFetchFailed.localizedDescription)
    }
}

private struct FakeAuthRepository: AuthRepository {
    let result: Result<AuthSession?, Error>

    func currentSession() async throws -> AuthSession? {
        try result.get()
    }

    func currentUserID() async throws -> UUID? {
        try result.get()?.userID
    }
}

private enum FakeBootstrapError: LocalizedError {
    case profileFetchFailed

    var errorDescription: String? {
        switch self {
        case .profileFetchFailed:
            return "Profile fetch failed."
        }
    }
}
