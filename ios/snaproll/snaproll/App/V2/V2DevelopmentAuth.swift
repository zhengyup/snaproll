import Foundation
import OSLog
import Supabase

enum DevelopmentAuthIdentity: String, CaseIterable, Identifiable, Sendable {
    case creator
    case participantA
    case participantB

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .creator:
            return "Creator"
        case .participantA:
            return "Participant A"
        case .participantB:
            return "Participant B"
        }
    }

    var debugLabel: String {
        switch self {
        case .creator:
            return "creator"
        case .participantA:
            return "participant-a"
        case .participantB:
            return "participant-b"
        }
    }
}

enum V2AuthenticationMode: Sendable, Equatable {
    case standard
    case development(DevelopmentAuthIdentity)
}

protocol DevelopmentAuthIdentityProviding: Sendable {
    func selectedIdentity() -> DevelopmentAuthIdentity
}

struct FixedDevelopmentAuthIdentityProvider: DevelopmentAuthIdentityProviding {
    let identity: DevelopmentAuthIdentity

    func selectedIdentity() -> DevelopmentAuthIdentity {
        identity
    }
}

struct PersistedDevelopmentAuthSession: Codable, Equatable, Sendable {
    let userID: UUID
    let accessToken: String
    let refreshToken: String
}

protocol DevelopmentAuthSessionPersisting: Sendable {
    func loadSession(for identity: DevelopmentAuthIdentity) -> PersistedDevelopmentAuthSession?
    func saveSession(_ session: PersistedDevelopmentAuthSession, for identity: DevelopmentAuthIdentity)
}

final class UserDefaultsDevelopmentAuthSessionStore: DevelopmentAuthSessionPersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSession(for identity: DevelopmentAuthIdentity) -> PersistedDevelopmentAuthSession? {
        guard let data = defaults.data(forKey: key(for: identity)) else {
            return nil
        }

        return try? decoder.decode(PersistedDevelopmentAuthSession.self, from: data)
    }

    func saveSession(_ session: PersistedDevelopmentAuthSession, for identity: DevelopmentAuthIdentity) {
        guard let data = try? encoder.encode(session) else {
            return
        }

        defaults.set(data, forKey: key(for: identity))
    }

    private func key(for identity: DevelopmentAuthIdentity) -> String {
        "snaproll.v2.development-auth.\(identity.rawValue)"
    }
}

struct DevelopmentAuthResolvedSession: Equatable, Sendable {
    let userID: UUID
    let accessToken: String
    let refreshToken: String
}

protocol DevelopmentAuthClient: Sendable {
    func restoreSession(accessToken: String, refreshToken: String) async throws -> DevelopmentAuthResolvedSession
    func signInAnonymously() async throws -> DevelopmentAuthResolvedSession
    func ensureProfile(displayName: String) async throws -> String?
    func signOut() async throws
}

struct DevelopmentAuthSessionResolver: Sendable {
    let identityProvider: any DevelopmentAuthIdentityProviding
    let sessionStore: any DevelopmentAuthSessionPersisting
    let client: any DevelopmentAuthClient
    let logger: Logger

    init(
        identityProvider: any DevelopmentAuthIdentityProviding,
        sessionStore: any DevelopmentAuthSessionPersisting,
        client: any DevelopmentAuthClient,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pzy.snaproll",
            category: "V2DevelopmentAuth"
        )
    ) {
        self.identityProvider = identityProvider
        self.sessionStore = sessionStore
        self.client = client
        self.logger = logger
    }

    func resolveSession() async throws -> AuthSession {
        let identity = identityProvider.selectedIdentity()
        logger.debug("Development auth enabled for identity \(identity.debugLabel, privacy: .public)")

        let resolvedSession: DevelopmentAuthResolvedSession
        if let persistedSession = sessionStore.loadSession(for: identity) {
            logger.debug("Restoring development session for \(identity.debugLabel, privacy: .public)")
            resolvedSession = try await client.restoreSession(
                accessToken: persistedSession.accessToken,
                refreshToken: persistedSession.refreshToken
            )
        } else {
            logger.debug("Creating anonymous development session for \(identity.debugLabel, privacy: .public)")
            resolvedSession = try await client.signInAnonymously()
        }

        let persistedSession = PersistedDevelopmentAuthSession(
            userID: resolvedSession.userID,
            accessToken: resolvedSession.accessToken,
            refreshToken: resolvedSession.refreshToken
        )
        sessionStore.saveSession(persistedSession, for: identity)

        do {
            let displayName = try await client.ensureProfile(displayName: identity.displayName)
            logger.debug("Profile ensure succeeded for \(identity.debugLabel, privacy: .public)")

            return AuthSession(
                userID: resolvedSession.userID,
                displayName: displayName ?? identity.displayName
            )
        } catch {
            logger.error(
                "Profile ensure failed for \(identity.debugLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }
}

private struct EnsureProfileRecord: Decodable {
    let id: UUID
    let display_name: String?
}

private struct EnsureProfileRequest: Encodable {
    let p_display_name: String?
}

struct SupabaseDevelopmentAuthClient: DevelopmentAuthClient, Sendable {
    let clientProvider: V2SupabaseClientProvider

    func restoreSession(accessToken: String, refreshToken: String) async throws -> DevelopmentAuthResolvedSession {
        let client = try await clientProvider.client()
        let session = try await client.auth.setSession(
            accessToken: accessToken,
            refreshToken: refreshToken
        )

        return DevelopmentAuthResolvedSession(
            userID: session.user.id,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken
        )
    }

    func signInAnonymously() async throws -> DevelopmentAuthResolvedSession {
        let client = try await clientProvider.client()
        let session = try await client.auth.signInAnonymously()

        return DevelopmentAuthResolvedSession(
            userID: session.user.id,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken
        )
    }

    func ensureProfile(displayName: String) async throws -> String? {
        let client = try await clientProvider.client()
        let response: EnsureProfileRecord = try await client
            .rpc(
                "ensure_profile",
                params: EnsureProfileRequest(p_display_name: displayName)
            )
            .single()
            .execute()
            .value

        return response.display_name
    }

    func signOut() async throws {
        let client = try await clientProvider.client()
        try await client.auth.signOut()
    }
}

final class DevelopmentAuthRepository: AuthRepository, @unchecked Sendable {
    private let resolver: DevelopmentAuthSessionResolver
    private let client: any DevelopmentAuthClient
    private let logger: Logger

    init(
        resolver: DevelopmentAuthSessionResolver,
        client: any DevelopmentAuthClient,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pzy.snaproll",
            category: "V2DevelopmentAuth"
        )
    ) {
        self.resolver = resolver
        self.client = client
        self.logger = logger
    }

    convenience init(
        clientProvider: V2SupabaseClientProvider,
        identityProvider: any DevelopmentAuthIdentityProviding,
        sessionStore: any DevelopmentAuthSessionPersisting
    ) {
        let client = SupabaseDevelopmentAuthClient(clientProvider: clientProvider)
        self.init(
            resolver: DevelopmentAuthSessionResolver(
                identityProvider: identityProvider,
                sessionStore: sessionStore,
                client: client
            ),
            client: client
        )
    }

    func currentSession() async throws -> AuthSession? {
        try await resolver.resolveSession()
    }

    func currentUserID() async throws -> UUID? {
        try await currentSession()?.userID
    }

    func signOut() async throws {
        logger.debug("Development sign-out requested")
        try await client.signOut()
    }
}
