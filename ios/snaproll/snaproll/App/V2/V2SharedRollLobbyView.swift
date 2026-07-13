import SwiftUI
#if os(iOS)
import UIKit
#endif

struct V2SharedRollLobbyView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: V2SharedRollLobbyViewModel
    @StateObject private var synchronizer: V2SharedStateSynchronizer
    @State private var isShowingCopyToast = false
    @State private var copyToastTask: Task<Void, Never>?
    @State private var isShowingExecutionView = false
    private let dependencies: V2DependencyContainer

    init(
        rollID: UUID,
        developmentIdentity: DevelopmentAuthIdentity? = nil,
        dependencies: V2DependencyContainer
    ) {
        self.dependencies = dependencies
        let viewModel = V2SharedRollLobbyViewModel(
            rollID: rollID,
            authRepository: dependencies.authRepository,
            rollRepository: dependencies.rollRepository,
            participantRepository: dependencies.participantRepository,
            inviteRepository: dependencies.inviteRepository,
            exposureRepository: dependencies.exposureRepository,
            exposureMirrorStore: dependencies.exposureMirrorStore,
            activeDevelopmentIdentityLabel: developmentIdentity?.displayName
        )
        _viewModel = StateObject(wrappedValue: viewModel)
        _synchronizer = StateObject(
            wrappedValue: V2SharedStateSynchronizer(rollID: rollID) { [weak viewModel] in
                guard let viewModel else {
                    return nil
                }

                return try await viewModel.refreshForSharedStateSynchronization()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading shared lobby")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .failed(let message):
                    statusCard(
                        title: "Unable to load lobby",
                        message: message,
                        showsRetry: true
                    )
                case .left:
                    statusCard(
                        title: "You left the roll",
                        message: "This shared lobby is no longer available for the current identity.",
                        showsRetry: false
                    )
                case .loaded:
                    if viewModel.canStartRoll
                        || viewModel.canRegenerateInvite
                        || viewModel.canLeaveRoll
                        || viewModel.roll?.status == .shooting
                        || viewModel.roll?.status == .readyToReveal
                        || viewModel.roll?.status == .revealed {
                        actionCard
                    }

                    if let actionErrorMessage = viewModel.actionErrorMessage {
                        statusCard(
                            title: "Action failed",
                            message: actionErrorMessage,
                            showsRetry: false
                        )
                    } else if let actionStatusMessage = viewModel.actionStatusMessage {
                        statusCard(
                            title: "Updated",
                            message: actionStatusMessage,
                            showsRetry: false
                        )
                    }

                    if let inviteToken = viewModel.visibleInviteToken {
                        inviteCard(token: inviteToken)
                    }

                    if viewModel.roll?.status == .shooting || viewModel.roll?.status == .readyToReveal || viewModel.roll?.status == .revealed {
                        exposurePlanCard
                    }

                    participantsCard

                    if viewModel.shouldShowDiagnostics, let diagnostics = viewModel.diagnosticsSummary {
                        diagnosticsCard(diagnostics)
                    }
                }
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
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingExecutionView) {
            V2PersonalRollDetailView(
                rollID: viewModel.rollID,
                dependencies: dependencies
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    Task {
                        await handleManualRefresh()
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if isShowingCopyToast {
                V2CopyFeedbackView(message: "Link copied")
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await handleInitialLoad()
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                await synchronizer.handleSceneActivity(isActive: newPhase == .active)
            }
        }
        .onDisappear {
            copyToastTask?.cancel()
            Task {
                await synchronizer.stop()
            }
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.canStartRoll {
                Button {
                    Task {
                        await viewModel.startRoll()
                        await synchronizer.refreshNow()
                    }
                } label: {
                    if viewModel.isStartingRoll {
                        ProgressView()
                            .tint(.black)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Start Roll")
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
                .disabled(viewModel.isStartingRoll)
            }

            if viewModel.canRegenerateInvite {
                Button {
                    Task {
                        await viewModel.regenerateInvite()
                        await synchronizer.refreshNow()
                    }
                } label: {
                    if viewModel.isRegeneratingInvite {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Regenerate Invite")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.black.opacity(0.28))
                )
                .disabled(viewModel.isRegeneratingInvite)
            }

            if viewModel.canLeaveRoll {
                Button {
                    Task {
                        await viewModel.leaveRoll()
                        await synchronizer.stop()
                    }
                } label: {
                    if viewModel.isLeavingRoll {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Leave Roll")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.red.opacity(0.34))
                )
                .disabled(viewModel.isLeavingRoll)
            }

            if viewModel.roll?.status == .shooting || viewModel.roll?.status == .readyToReveal || viewModel.roll?.status == .revealed {
                Button {
                    isShowingExecutionView = true
                } label: {
                    Text(viewModel.roll?.status == .revealed ? "Open Gallery" : "Continue Roll")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.title)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)

            Text(viewModel.statusLabel)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))

            if let activeIdentityLabel = viewModel.activeIdentityLabel {
                Text("Current dev identity: \(activeIdentityLabel)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.74))
            }

            Text(viewModel.isCreator ? "You are the creator." : "Waiting room for shared participants.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))

            if !viewModel.isMutableLobby {
                Text("This lobby is now locked. The exposure plan has been created in the cloud.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func inviteCard(token: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Invite Token")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Share this code with another development identity to join the lobby.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))

            Button {
                handleInviteCopy(token)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(token)
                        .font(.body.monospaced())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Tap to copy")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black.opacity(0.18))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var participantsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participants")
                .font(.headline)
                .foregroundStyle(.white)

            Text(viewModel.participantCountLabel)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.64))

            ForEach(viewModel.participants, id: \.id) { participant in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(participant.display_name ?? "Unnamed Participant")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if participant.user_id == viewModel.currentUserID {
                            badge("You")
                        }

                        if participant.user_id == viewModel.roll?.creator_id {
                            badge("Creator")
                        }
                    }

                    Text(participant.status.rawValue.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))

                    if viewModel.canRemoveParticipant(participant) {
                        Button {
                            Task {
                                await viewModel.removeParticipant(id: participant.id)
                                await synchronizer.refreshNow()
                            }
                        } label: {
                            if viewModel.activeRemovalParticipantID == participant.id {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("Remove Participant")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red.opacity(0.9))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black.opacity(0.18))
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var exposurePlanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exposure Plan")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Cloud exposure slots are now authoritative for this participant.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.68))

            Text("\(viewModel.mirroredExposureCount) mirrored exposure slot\(viewModel.mirroredExposureCount == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func statusCard(title: String, message: String, showsRetry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.72))

            if showsRetry {
                Button("Retry") {
                    Task {
                        await handleRetryLoad()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func diagnosticsCard(_ diagnostics: V2SharedRollLobbyViewModel.DiagnosticsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Development Diagnostics")
                .font(.headline)
                .foregroundStyle(.white)

            diagnosticsLine("Roll ID", diagnostics.rollID.uuidString)
            diagnosticsLine("Creator ID", diagnostics.creatorID.uuidString)
            diagnosticsLine("Participant count", "\(diagnostics.participantCount)")
            diagnosticsLine("Roll status", diagnostics.rollStatus.rawValue)
            diagnosticsLine("Mirrored exposures", "\(diagnostics.mirroredExposureCount)")
            diagnosticsLine("Polling active", synchronizer.snapshot.isPollingActive ? "Yes" : "No")
            diagnosticsLine("Polling blocked", synchronizer.snapshot.isPollingBlocked ? "Yes" : "No")

            if let currentIntervalSeconds = synchronizer.snapshot.currentIntervalSeconds {
                diagnosticsLine("Polling interval", String(format: "%.0f s", currentIntervalSeconds))
            }

            diagnosticsLine("Poll count", "\(synchronizer.snapshot.pollCount)")

            if let latestBackendState = synchronizer.snapshot.latestBackendState {
                diagnosticsLine("Latest backend state", latestBackendState.rawValue)
            }

            if let lastRefreshAt = synchronizer.snapshot.lastRefreshAt {
                diagnosticsLine("Last refresh", lastRefreshAt.formatted(date: .abbreviated, time: .standard))
            }

            if let lastRefreshDurationMilliseconds = synchronizer.snapshot.lastRefreshDurationMilliseconds {
                diagnosticsLine("Refresh duration", String(format: "%.1f ms", lastRefreshDurationMilliseconds))
            }

            if let lastErrorMessage = synchronizer.snapshot.lastErrorMessage {
                diagnosticsLine("Last polling error", lastErrorMessage)
            }

            if let currentParticipantID = diagnostics.currentParticipantID {
                diagnosticsLine("Current participant ID", currentParticipantID.uuidString)
            }

            ForEach(Array(diagnostics.participantIDs.enumerated()), id: \.offset) { index, participantID in
                diagnosticsLine("Participant \(index + 1)", participantID.uuidString)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func diagnosticsLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))

            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
        }
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.94, green: 0.76, blue: 0.13))
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.white.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }

    private func handleInviteCopy(_ inviteToken: String) {
        #if os(iOS)
        UIPasteboard.general.string = inviteToken
        #endif

        guard !isShowingCopyToast else {
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            isShowingCopyToast = true
        }

        copyToastTask?.cancel()
        copyToastTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                withAnimation(.easeIn(duration: 0.18)) {
                    isShowingCopyToast = false
                }
                copyToastTask = nil
            }
        }
    }

    private func handleInitialLoad() async {
        await viewModel.load()

        guard case .loaded = viewModel.state else {
            return
        }

        synchronizer.seedLatestKnownState(viewModel.roll?.status)
        await synchronizer.start()
    }

    private func handleRetryLoad() async {
        await viewModel.refresh()

        guard case .loaded = viewModel.state else {
            return
        }

        synchronizer.seedLatestKnownState(viewModel.roll?.status)
        await synchronizer.start()
    }

    private func handleManualRefresh() async {
        if case .loaded = viewModel.state {
            await synchronizer.refreshNow()
        } else {
            await handleRetryLoad()
        }
    }
}
