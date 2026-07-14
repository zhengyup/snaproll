import Combine
import Foundation
import OSLog
import SwiftUI

enum V2SessionState: Equatable, Sendable {
    case loading
    case signedOut
    case signedIn(AuthSession)
    case failed(String)
}

struct V2SessionBootstrapper: Sendable {
    let authRepository: any AuthRepository

    func bootstrap() async throws -> V2SessionState {
        guard let session = try await authRepository.currentSession() else {
            return .signedOut
        }

        return .signedIn(session)
    }

    func signOut() async throws {
        try await authRepository.signOut()
    }
}

@MainActor
final class V2SessionStore: ObservableObject {
    @Published private(set) var state: V2SessionState = .loading

    private let bootstrapper: V2SessionBootstrapper
    private let logger: Logger
    private var hasBootstrapped = false

    init(
        bootstrapper: V2SessionBootstrapper,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pzy.snaproll",
            category: "V2SessionBootstrap"
        )
    ) {
        self.bootstrapper = bootstrapper
        self.logger = logger
    }

    convenience init(
        authRepository: any AuthRepository,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pzy.snaproll",
            category: "V2SessionBootstrap"
        )
    ) {
        self.init(
            bootstrapper: V2SessionBootstrapper(authRepository: authRepository),
            logger: logger
        )
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else {
            return
        }

        hasBootstrapped = true
        await bootstrap()
    }

    func retry() async {
        hasBootstrapped = true
        await bootstrap()
    }

    func signOut() async {
        do {
            try await bootstrapper.signOut()
            transition(to: .signedOut, reason: "Signed out")
        } catch {
            transition(
                to: .failed(error.localizedDescription),
                reason: "Sign out failed: \(error.localizedDescription)"
            )
        }
    }

    private func bootstrap() async {
        transition(to: .loading, reason: "Starting bootstrap")

        do {
            let resolvedState = try await bootstrapper.bootstrap()
            transition(to: resolvedState, reason: "Bootstrap resolved")
        } catch {
            transition(
                to: .failed(error.localizedDescription),
                reason: "Bootstrap failed: \(error.localizedDescription)"
            )
        }
    }

    private func transition(to nextState: V2SessionState, reason: String) {
        logger.debug("\(reason, privacy: .public)")
        state = nextState
        logger.debug("Session state -> \(String(describing: nextState), privacy: .public)")
    }
}

struct V2BootstrapEntryView: View {
    @StateObject private var sessionStore: V2SessionStore
    @ObservedObject private var inviteRoutingCoordinator: V2InviteRoutingCoordinator
    private let dependencies: V2DependencyContainer
    private let developmentAuthSettings: DevelopmentAuthSettings

    init(
        sessionStore: V2SessionStore,
        dependencies: V2DependencyContainer,
        developmentAuthSettings: DevelopmentAuthSettings,
        inviteRoutingCoordinator: V2InviteRoutingCoordinator
    ) {
        _sessionStore = StateObject(wrappedValue: sessionStore)
        _inviteRoutingCoordinator = ObservedObject(wrappedValue: inviteRoutingCoordinator)
        self.dependencies = dependencies
        self.developmentAuthSettings = developmentAuthSettings
    }

    var body: some View {
        Group {
            switch sessionStore.state {
            case .loading:
                ProgressView("Preparing Snaproll V2")
                    .progressViewStyle(.circular)
            case .signedOut:
                V2BootstrapStatusView(
                    title: "V2 Session Required",
                    message: "No Supabase session was found. V2 auth UI is not wired yet, so the safe path is to keep using the V1 experience until that phase is ready."
                )
            case .signedIn:
                V2CloudHomeView(
                    sessionStore: sessionStore,
                    developmentAuthSettings: developmentAuthSettings,
                    dependencies: dependencies,
                    inviteRoutingCoordinator: inviteRoutingCoordinator
                )
            case .failed(let message):
                VStack(spacing: 20) {
                    V2BootstrapStatusView(
                        title: "Unable to Start V2",
                        message: message
                    )

                    Button("Retry") {
                        Task {
                            await sessionStore.retry()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if AppConfig.V2.showsDevelopmentIdentityControls, !isShowingCloudHome {
                V2DevelopmentIdentityBadge(state: sessionStore.state)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
        .task {
            await sessionStore.bootstrapIfNeeded()
        }
    }

    private var isShowingCloudHome: Bool {
        if case .signedIn = sessionStore.state {
            return true
        }

        return false
    }
}

private struct V2BootstrapStatusView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
        }
        .padding(24)
    }
}

private struct V2DevelopmentIdentityBadge: View {
    let state: V2SessionState

    private var identityLabel: String {
        AppConfig.V2.developmentIdentity.displayName
    }

    private var sessionLabel: String? {
        guard case .signedIn(let session) = state else {
            return nil
        }

        return session.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dev User")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if sessionLabel == nil || sessionLabel == identityLabel {
                Text(identityLabel)
                    .font(.caption.weight(.semibold))
            } else {
                Text(identityLabel)
                    .font(.caption.weight(.semibold))

                Text(sessionLabel ?? identityLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}
