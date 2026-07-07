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

    init(sessionStore: V2SessionStore) {
        _sessionStore = StateObject(wrappedValue: sessionStore)
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
                HomeView()
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
        .task {
            await sessionStore.bootstrapIfNeeded()
        }
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
