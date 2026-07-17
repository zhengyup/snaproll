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
                VStack(alignment: .leading, spacing: 18) {
                    V2CloudHomeHeader(
                        onCreateRoll: {
                            isShowingCreateRoll = true
                        },
                        onRefresh: {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                    )
                    .padding(.top, 12)

                    if let inviteToken = viewModel.lastCreatedSharedInviteToken {
                        V2CloudInviteSharePanel(
                            rollTitle: viewModel.lastCreatedSharedRollTitle ?? "Shared Roll",
                            inviteToken: inviteToken
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
                        participantRepository: dependencies.participantRepository,
                        exposureMirrorStore: dependencies.exposureMirrorStore,
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
                        Color(red: 0.995, green: 0.976, blue: 0.94),
                        Color(red: 0.965, green: 0.94, blue: 0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingCreateRoll) {
                V2CloudCreateRollView(
                    draftTitle: $viewModel.draftTitle,
                    selectedCreationType: $viewModel.selectedCreationType,
                    selectedFilmStock: $viewModel.selectedFilmStock,
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

private struct V2CloudHomeHeader: View {
    let onCreateRoll: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
                Text("snaproll")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.0)
                    .foregroundStyle(Color(red: 0.13, green: 0.10, blue: 0.09))

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.16, green: 0.12, blue: 0.10))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.72), in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Refresh rolls")
            }

            HStack(alignment: .center) {
                Text("My Rolls")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.09))

                Spacer()

                Button(action: onCreateRoll) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("New Roll")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color(red: 0.86, green: 0.34, blue: 0.05))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.74), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color(red: 0.86, green: 0.34, blue: 0.05).opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
                }
                .accessibilityLabel("Create new roll")
            }
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
    @Binding var selectedFilmStock: FilmStock
    @Binding var selectedExposureCount: Int
    let isCreating: Bool
    let onCreate: () async -> Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create Roll")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.10))

                        Text("Choose a name, type, and exposure count.")
                            .font(.subheadline)
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                    .padding(.top, 22)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Roll Name")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.14, green: 0.13, blue: 0.12))

                        TextField("Untitled Roll", text: $draftTitle)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.white.opacity(0.72))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            }
                            .foregroundStyle(Color(red: 0.12, green: 0.11, blue: 0.10))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Choose Roll Type")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color(red: 0.14, green: 0.13, blue: 0.12))

                            Text("Pick the vibe for your roll.")
                                .font(.subheadline)
                                .foregroundStyle(Color.black.opacity(0.52))
                        }

                        HStack(spacing: 14) {
                            V2RollStyleSelectionCard(
                                filmStock: .kodakGold200,
                                selectedFilmStock: $selectedFilmStock
                            )

                            V2RollStyleSelectionCard(
                                filmStock: .fujifilmSuperia400,
                                selectedFilmStock: $selectedFilmStock
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Exposures")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color(red: 0.14, green: 0.13, blue: 0.12))

                            Text("Choose how many shots are on this roll.")
                                .font(.subheadline)
                                .foregroundStyle(Color.black.opacity(0.52))
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(AppConfig.V2.createRollExposureCounts, id: \.self) { count in
                                    V2ExposureSelectionPill(
                                        count: count,
                                        isSelected: selectedExposureCount == count,
                                        accent: selectedFilmStock.createRollAccent
                                    ) {
                                        selectedExposureCount = count
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
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Roll")
                                .font(.title3.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selectedFilmStock.createRollAccent)
                    )
                    .disabled(isCreating)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.995, green: 0.976, blue: 0.94),
                        Color(red: 0.965, green: 0.94, blue: 0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color(red: 0.92, green: 0.29, blue: 0.02))
                    }
                    .disabled(isCreating)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(red: 0.92, green: 0.29, blue: 0.02))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.62), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    }
                    .disabled(isCreating)
                }
            }
            .onAppear {
                selectedCreationType = .personal
                if !FilmStock.allCases.contains(selectedFilmStock) {
                    selectedFilmStock = .kodakGold200
                }
                if !AppConfig.V2.createRollExposureCounts.contains(selectedExposureCount),
                   let defaultCount = AppConfig.V2.createRollExposureCounts.first {
                    selectedExposureCount = defaultCount
                }
            }
        }
    }
}

private struct V2RollStyleSelectionCard: View {
    let filmStock: FilmStock
    @Binding var selectedFilmStock: FilmStock

    private var isSelected: Bool {
        selectedFilmStock == filmStock
    }

    var body: some View {
        Button {
            selectedFilmStock = filmStock
        } label: {
            VStack(spacing: 12) {
                HStack {
                    Spacer()

                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? filmStock.createRollAccent : Color.black.opacity(0.20), lineWidth: 1.5)
                            .frame(width: 22, height: 22)

                        if isSelected {
                            Circle()
                                .fill(filmStock.createRollAccent)
                                .frame(width: 22, height: 22)

                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                Image(filmStock.createRollSpriteName)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(height: 90)
                    .accessibilityHidden(true)

                Text(filmStock.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.11, blue: 0.10))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .frame(height: 242)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? filmStock.createRollAccent.opacity(0.06) : .white.opacity(0.68))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? filmStock.createRollAccent : Color.black.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct V2ExposureSelectionPill: View {
    let count: Int
    let isSelected: Bool
    let accent: Color
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.title2.weight(.bold))

                Text("shots")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
            }
            .frame(width: 78, height: 70)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? accent : Color.black.opacity(0.58))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? accent.opacity(0.08) : .white.opacity(0.64))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.55) : Color.black.opacity(0.08), lineWidth: 1)
        }
    }
}

private extension FilmStock {
    var createRollSpriteName: String {
        switch self {
        case .kodakGold200, .ilfordHP5Plus:
            return "started_flame"
        case .fujifilmSuperia400:
            return "started_ice"
        }
    }

    var createRollAccent: Color {
        switch self {
        case .kodakGold200, .ilfordHP5Plus:
            return Color(red: 0.95, green: 0.30, blue: 0.00)
        case .fujifilmSuperia400:
            return Color(red: 0.20, green: 0.56, blue: 0.96)
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
    let participantRepository: any ParticipantRepository
    let exposureMirrorStore: any ExposureMirrorStore
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case .idle, .loading:
                ProgressView("Loading rolls")
                    .tint(Color(red: 0.86, green: 0.34, blue: 0.05))
                    .foregroundStyle(Color.black.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            case .signedOut:
                V2CloudStatusCard(
                    title: "Session unavailable",
                    message: "No authenticated V2 session was available for loading personal rolls."
                )
            case .empty:
                V2CloudStatusCard(
                    title: "No rolls yet",
                    message: emptyStateMessage
                )
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    V2CloudStatusCard(
                        title: "Unable to load rolls",
                        message: message
                    )

                    Button("Retry Load", action: onRetry)
                        .buttonStyle(.bordered)
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
                            V2CloudRollCard(
                                roll: roll,
                                participantRepository: participantRepository,
                                exposureMirrorStore: exposureMirrorStore
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyStateMessage: String {
        if AppConfig.V2.showsDeveloperUI {
            return "Use the + button, then switch identities to verify user-scoped cloud visibility."
        }

        return "Create your first roll and start making memories"
    }
}

private struct V2CloudStatusCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.14, green: 0.11, blue: 0.10))

            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.black.opacity(0.56))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct V2CloudRollCard: View {
    let roll: LocalRoll
    let participantRepository: any ParticipantRepository
    let exposureMirrorStore: any ExposureMirrorStore
    @State private var participantCount: Int?
    @State private var capturedExposureCount: Int?

    var body: some View {
        HStack(spacing: 16) {
            Image(spriteName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 82, height: 82)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(roll.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.09))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusAccent)
                        .frame(width: 7, height: 7)

                    Text(statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(statusAccent)
                }

                HStack(spacing: 6) {
                    if roll.type == .shared && roll.status == .waitingForParticipants {
                        Image(systemName: "person.2")
                            .font(.caption)
                    }

                    Text(secondaryMetadata)
                        .font(.subheadline)
                }
                .foregroundStyle(Color.black.opacity(0.48))
            }

            Spacer(minLength: 10)

            trailingContent

            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.26))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.88))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 14, x: 0, y: 7)
        .task(id: roll.id) {
            await loadCardMetadata()
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if roll.status == .revealed || roll.status == .readyToReveal {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                Text("revealed")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Color.black.opacity(0.42))
        } else if roll.type == .shared && roll.status == .waitingForParticipants {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(participantCount ?? 1) / 10")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.09))
                Text("joined")
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.44))
                progressBar(progress: min(Double(participantCount ?? 1) / 10.0, 1.0))
            }
            .frame(width: 92, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(capturedCount) / \(roll.exposures_per_participant)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.09))
                Text("shots")
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.44))
                progressBar(progress: exposureProgress)
            }
            .frame(width: 92, alignment: .leading)
        }
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.07))
                Capsule()
                    .fill(styleAccent)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 5)
    }

    private var statusText: String {
        switch roll.status {
        case .draft, .shooting:
            return "started"
        case .waitingForParticipants:
            return "waiting"
        case .readyToReveal, .revealed:
            return "completed"
        }
    }

    private var secondaryMetadata: String {
        if roll.type == .shared && roll.status == .waitingForParticipants {
            return "\(participantCount ?? 1)/10 joined"
        }

        return Self.dateFormatter.string(from: roll.created_at)
    }

    private var capturedCount: Int {
        if roll.status == .readyToReveal || roll.status == .revealed {
            return roll.exposures_per_participant
        }

        return capturedExposureCount ?? 0
    }

    private var exposureProgress: Double {
        guard roll.exposures_per_participant > 0 else {
            return 0
        }

        return min(Double(capturedCount) / Double(roll.exposures_per_participant), 1.0)
    }

    private var spriteName: String {
        "\(spriteLifecycle)_\(spriteStyle)"
    }

    private var spriteLifecycle: String {
        switch roll.status {
        case .draft, .shooting:
            return "started"
        case .waitingForParticipants:
            return "waiting"
        case .readyToReveal, .revealed:
            return "completed"
        }
    }

    private var spriteStyle: String {
        isCoolRoll ? "ice" : "flame"
    }

    private var isCoolRoll: Bool {
        FilmStock(rawValue: roll.film_stock_id) == .fujifilmSuperia400
    }

    private var styleAccent: Color {
        isCoolRoll
            ? Color(red: 0.12, green: 0.54, blue: 0.96)
            : Color(red: 0.90, green: 0.38, blue: 0.04)
    }

    private var statusAccent: Color {
        switch roll.status {
        case .readyToReveal, .revealed:
            return Color(red: 0.28, green: 0.58, blue: 0.28)
        case .draft, .waitingForParticipants, .shooting:
            return styleAccent
        }
    }

    private func loadCardMetadata() async {
        if roll.type == .shared && roll.status == .waitingForParticipants {
            if let participants = try? await participantRepository.fetchParticipants(forRollID: roll.id) {
                participantCount = participants.count
            }
        }

        if let exposures = try? await exposureMirrorStore.fetchExposures(forRollID: roll.id) {
            capturedExposureCount = exposures.filter { $0.captured_at != nil || $0.sync_state != .empty }.count
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}
