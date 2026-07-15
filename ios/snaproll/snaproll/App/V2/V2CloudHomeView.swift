import SwiftUI

struct V2CloudHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var sessionStore: V2SessionStore
    @ObservedObject var developmentAuthSettings: DevelopmentAuthSettings
    @ObservedObject var inviteRoutingCoordinator: V2InviteRoutingCoordinator
    @StateObject private var viewModel: V2CloudHomeViewModel
    @State private var isShowingCreateRoll = false

    init(
        sessionStore: V2SessionStore,
        developmentAuthSettings: DevelopmentAuthSettings,
        dependencies: V2DependencyContainer,
        inviteRoutingCoordinator: V2InviteRoutingCoordinator
    ) {
        self.sessionStore = sessionStore
        self.developmentAuthSettings = developmentAuthSettings
        _inviteRoutingCoordinator = ObservedObject(wrappedValue: inviteRoutingCoordinator)
        self.dependencies = dependencies
        self.pendingRecoveryCoordinator = dependencies.pendingExposureRecoveryCoordinator
        _viewModel = StateObject(
            wrappedValue: V2CloudHomeViewModel(
                authRepository: dependencies.authRepository,
                rollRepository: dependencies.rollRepository,
                participantRepository: dependencies.participantRepository
            )
        )
    }

    private let dependencies: V2DependencyContainer
    private let pendingRecoveryCoordinator: any PendingExposureRecovering

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if AppConfig.V2.showsDevelopmentIdentityControls {
                        V2CloudIdentityPanel(
                            session: viewModel.currentSession,
                            selectedIdentity: developmentAuthSettings.selectedIdentity,
                            isSwitchingIdentity: sessionStore.state == .loading,
                            onIdentitySelected: handleIdentitySelection
                        )
                    }

                    if let inviteToken = viewModel.lastCreatedSharedInviteToken {
                        V2CloudInviteSharePanel(
                            rollTitle: viewModel.lastCreatedSharedRollTitle ?? "Shared Roll",
                            inviteToken: inviteToken
                        )
                    }

                    if AppConfig.V2.showsDeveloperUI {
                        V2CloudJoinRollPanel(
                            inviteToken: $viewModel.joinInviteToken,
                            isJoining: viewModel.isJoiningRoll,
                            onJoin: {
                                Task {
                                    await viewModel.joinSharedRoll()
                                }
                            }
                        )
                    }

                    if let actionErrorMessage = viewModel.actionErrorMessage {
                        V2CloudStatusCard(
                            title: "Action failed",
                            message: actionErrorMessage
                        )
                    } else if let actionStatusMessage = viewModel.actionStatusMessage {
                        V2CloudStatusCard(
                            title: "Updated",
                            message: actionStatusMessage
                        )
                    }

                    V2CloudRollListSection(
                        state: viewModel.state,
                        rolls: viewModel.rolls,
                        selectedIdentity: developmentAuthSettings.selectedIdentity,
                        dependencies: dependencies,
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
            .navigationTitle(AppConfig.V2.navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingCreateRoll = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel("Create roll")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .disabled(sessionStore.state == .loading)
                }
            }
            .sheet(isPresented: $isShowingCreateRoll) {
                V2CloudCreateRollView(
                    draftTitle: $viewModel.draftTitle,
                    selectedCreationType: $viewModel.selectedCreationType,
                    selectedExposureCount: $viewModel.selectedExposureCount,
                    isCreating: viewModel.isCreatingRoll,
                    onCreate: {
                        await viewModel.createRoll()
                    }
                )
            }
            .sheet(item: pendingInviteBinding) { invite in
                V2RollInvitePreviewView(
                    invite: invite,
                    dependencies: dependencies,
                    onDismissInvite: {
                        inviteRoutingCoordinator.dismissPendingInvite()
                    },
                    onJoined: { rollID in
                        inviteRoutingCoordinator.completeJoin(rollID: rollID)
                        Task {
                            await viewModel.load()
                        }
                    }
                )
            }
            .navigationDestination(item: $inviteRoutingCoordinator.joinedRoute) { route in
                V2SharedRollLobbyView(
                    rollID: route.rollID,
                    developmentIdentity: developmentAuthSettings.selectedIdentity,
                    dependencies: dependencies
                )
            }
            .alert("Invite link problem", isPresented: invalidInviteAlertBinding) {
                Button("OK") {
                    inviteRoutingCoordinator.dismissInvalidInviteMessage()
                }
            } message: {
                Text(inviteRoutingCoordinator.invalidInviteMessage ?? "This Snaproll invite link is not valid.")
            }
        }
        .task(id: signedInUserID) {
            await handleSessionScopedLoadAndRecovery()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, signedInUserID != nil else {
                return
            }

            Task {
                await handleForegroundRecovery()
            }
        }
    }

    private var pendingInviteBinding: Binding<RollInviteLink?> {
        Binding(
            get: { inviteRoutingCoordinator.pendingInvite },
            set: { newValue in
                if newValue == nil {
                    inviteRoutingCoordinator.dismissPendingInvite()
                }
            }
        )
    }

    private var invalidInviteAlertBinding: Binding<Bool> {
        Binding(
            get: { inviteRoutingCoordinator.invalidInviteMessage != nil },
            set: { isPresented in
                if !isPresented {
                    inviteRoutingCoordinator.dismissInvalidInviteMessage()
                }
            }
        )
    }

    private var signedInUserID: UUID? {
        guard case .signedIn(let session) = sessionStore.state else {
            return nil
        }

        return session.userID
    }

    private func handleSessionScopedLoadAndRecovery() async {
        await viewModel.load()

        guard signedInUserID != nil else {
            return
        }

        await pendingRecoveryCoordinator.recoverPendingWorkForCurrentSession()
        await viewModel.load()
    }

    private func handleForegroundRecovery() async {
        await pendingRecoveryCoordinator.recoverPendingWorkForCurrentSession()
        await viewModel.load()
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

private struct V2CloudCreateRollView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draftTitle: String
    @Binding var selectedCreationType: V2Domain.RollType
    @Binding var selectedExposureCount: Int
    let isCreating: Bool
    let onCreate: () async -> Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create Roll")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(.white)

                        Text("Choose a name, type, and exposure count.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.62))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Roll Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))

                        TextField("Untitled Roll", text: $draftTitle)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.white.opacity(0.08))
                            )
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Roll Type")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))

                        Picker("Roll Type", selection: $selectedCreationType) {
                            Text("Personal").tag(V2Domain.RollType.personal)
                            Text("Shared").tag(V2Domain.RollType.shared)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Exposures")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(AppConfig.V2.createRollExposureCounts, id: \.self) { count in
                                    Button {
                                        selectedExposureCount = count
                                    } label: {
                                        VStack(spacing: 2) {
                                            Text("\(count)")
                                                .font(.title3.weight(.semibold))
                                            Text("shots")
                                                .font(.caption2.weight(.medium))
                                                .textCase(.uppercase)
                                                .opacity(0.7)
                                        }
                                        .frame(width: 72, height: 64)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(selectedExposureCount == count ? .black : .white)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(selectedExposureCount == count ? Color(red: 0.94, green: 0.76, blue: 0.13) : .white.opacity(0.08))
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(selectedExposureCount == count ? .clear : .white.opacity(0.12), lineWidth: 1)
                                    }
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    Button {
                        Task {
                            let didCreate = await onCreate()
                            if didCreate {
                                dismiss()
                            }
                        }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .tint(.black)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Roll")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.94, green: 0.76, blue: 0.13))
                    )
                    .disabled(isCreating)
                    .padding(.top, 4)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
            .onAppear {
                if !AppConfig.V2.createRollExposureCounts.contains(selectedExposureCount),
                   let defaultCount = AppConfig.V2.createRollExposureCounts.first {
                    selectedExposureCount = defaultCount
                }
            }
        }
    }
}

private struct V2CloudInviteSharePanel: View {
    let rollTitle: String
    let inviteToken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shared Lobby Ready")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))

            Text("Invite for \(rollTitle)")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))

            if let inviteLink = RollInviteLink(token: inviteToken) {
                ShareLink(
                    item: inviteLink.url,
                    subject: Text("Join my Snaproll"),
                    message: Text("Join my Snaproll: \(inviteLink.url.absoluteString)")
                ) {
                    Text("Share Invite")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.94, green: 0.76, blue: 0.13))
                )

                if AppConfig.V2.showsDeveloperUI {
                    Text(inviteLink.url.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.58))
                        .textSelection(.enabled)
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

private struct V2CloudJoinRollPanel: View {
    @Binding var inviteToken: String
    let isJoining: Bool
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Join Shared Roll")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))

            TextField("Paste invite token", text: $inviteToken)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .foregroundStyle(.white)

            Button {
                onJoin()
            } label: {
                if isJoining {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Join Shared Roll")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
            .disabled(isJoining)

            Text("Use the invite token from the shared lobby creator to join with the current development identity.")
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
    let selectedIdentity: DevelopmentAuthIdentity
    let dependencies: V2DependencyContainer
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Rolls")
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
                    message: emptyStateMessage
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
                        NavigationLink {
                            if roll.type == .shared && roll.status == .waitingForParticipants {
                                V2SharedRollLobbyView(
                                    rollID: roll.id,
                                    developmentIdentity: selectedIdentity,
                                    dependencies: dependencies
                                )
                            } else {
                                V2PersonalRollDetailView(
                                    rollID: roll.id,
                                    dependencies: dependencies,
                                    developmentIdentity: selectedIdentity
                                )
                            }
                        } label: {
                            V2CloudRollCard(roll: roll)
                        }
                        .buttonStyle(.plain)
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

    private var emptyStateMessage: String {
        if AppConfig.V2.showsDeveloperUI {
            return "Use the + button, then switch identities to verify user-scoped cloud visibility."
        }

        return "Create your first roll to start building your memories."
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
                Text("\(roll.type.rawValue.capitalized) · \(statusLabel)")
                Spacer()
                Text("\(roll.exposures_per_participant) exp")
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
