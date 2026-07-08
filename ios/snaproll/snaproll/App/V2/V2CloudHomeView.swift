import SwiftUI

struct V2CloudHomeView: View {
    @ObservedObject var sessionStore: V2SessionStore
    @ObservedObject var developmentAuthSettings: DevelopmentAuthSettings
    @StateObject private var viewModel: V2CloudHomeViewModel

    init(
        sessionStore: V2SessionStore,
        developmentAuthSettings: DevelopmentAuthSettings,
        dependencies: V2DependencyContainer
    ) {
        self.sessionStore = sessionStore
        self.developmentAuthSettings = developmentAuthSettings
        _viewModel = StateObject(
            wrappedValue: V2CloudHomeViewModel(
                authRepository: dependencies.authRepository,
                rollRepository: dependencies.rollRepository
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    V2CloudIdentityPanel(
                        session: viewModel.currentSession,
                        selectedIdentity: developmentAuthSettings.selectedIdentity,
                        isSwitchingIdentity: sessionStore.state == .loading,
                        onIdentitySelected: handleIdentitySelection
                    )

                    V2CloudCreateRollPanel(
                        draftTitle: $viewModel.draftTitle,
                        isCreating: viewModel.isCreatingRoll,
                        onCreate: {
                            Task {
                                await viewModel.createPersonalRoll()
                            }
                        }
                    )

                    V2CloudRollListSection(
                        state: viewModel.state,
                        rolls: viewModel.rolls,
                        onRetry: {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                    )
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.06, blue: 0.05),
                        Color(red: 0.11, green: 0.09, blue: 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("V2 Cloud Rolls")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .disabled(sessionStore.state == .loading)
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .task(id: signedInUserID) {
            guard signedInUserID != nil else {
                return
            }

            await viewModel.load()
        }
    }

    private var signedInUserID: UUID? {
        guard case .signedIn(let session) = sessionStore.state else {
            return nil
        }

        return session.userID
    }

    private func handleIdentitySelection(_ identity: DevelopmentAuthIdentity) {
        Task {
            await developmentAuthSettings.selectIdentity(identity)
            await sessionStore.retry()
        }
    }
}

private struct V2CloudIdentityPanel: View {
    let session: AuthSession?
    let selectedIdentity: DevelopmentAuthIdentity
    let isSwitchingIdentity: Bool
    let onIdentitySelected: (DevelopmentAuthIdentity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Development Session")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))

            VStack(alignment: .leading, spacing: 8) {
                Text("Identity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))

                Picker("Development Identity", selection: identityBinding) {
                    ForEach(DevelopmentAuthIdentity.allCases) { identity in
                        Text(identity.displayName).tag(identity)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isSwitchingIdentity)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session?.displayName ?? selectedIdentity.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(sessionUserLabel)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var identityBinding: Binding<DevelopmentAuthIdentity> {
        Binding(
            get: { selectedIdentity },
            set: { onIdentitySelected($0) }
        )
    }

    private var sessionUserLabel: String {
        guard let session else {
            return "No active session"
        }

        return "User \(session.userID.uuidString.prefix(8))"
    }
}

private struct V2CloudCreateRollPanel: View {
    @Binding var draftTitle: String
    let isCreating: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Personal Roll")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))

            TextField("Untitled Roll", text: $draftTitle)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .foregroundStyle(.white)

            Button {
                onCreate()
            } label: {
                if isCreating {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Create Cloud Roll")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.94, green: 0.76, blue: 0.13))
            )
            .disabled(isCreating)

            Text("Creates a PERSONAL roll through the V2 Supabase RPC path with 12 exposures and a single participant.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct V2CloudRollListSection: View {
    let state: V2CloudHomeState
    let rolls: [LocalRoll]
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visible Cloud Rolls")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))

            switch state {
            case .idle, .loading:
                ProgressView("Loading cloud rolls")
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            case .signedOut:
                V2CloudStatusCard(
                    title: "Session unavailable",
                    message: "No authenticated V2 session was available for loading personal rolls."
                )
            case .empty:
                V2CloudStatusCard(
                    title: "No personal rolls yet",
                    message: "Create one above, then switch identities to verify user-scoped cloud visibility."
                )
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    V2CloudStatusCard(
                        title: "Unable to load rolls",
                        message: message
                    )

                    Button("Retry Load", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            case .loaded:
                VStack(spacing: 12) {
                    ForEach(rolls, id: \.id) { roll in
                        V2CloudRollCard(roll: roll)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct V2CloudStatusCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.16))
        )
    }
}

private struct V2CloudRollCard: View {
    let roll: LocalRoll

    private var statusLabel: String {
        roll.status.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    private var filmLabel: String {
        FilmStock(rawValue: roll.film_stock_id)?.displayName ?? roll.film_stock_id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(roll.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text(filmLabel)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            HStack {
                Text(statusLabel)
                Spacer()
                Text("12 exp")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.18))
        )
    }
}
