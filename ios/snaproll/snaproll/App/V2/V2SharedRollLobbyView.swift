import SwiftUI
#if os(iOS)
import UIKit
#endif

struct V2SharedRollLobbyView: View {
    @StateObject private var viewModel: V2SharedRollLobbyViewModel
    @State private var isShowingCopyToast = false
    @State private var copyToastTask: Task<Void, Never>?

    init(
        rollID: UUID,
        developmentIdentity: DevelopmentAuthIdentity? = nil,
        dependencies: V2DependencyContainer
    ) {
        _viewModel = StateObject(
            wrappedValue: V2SharedRollLobbyViewModel(
                rollID: rollID,
                authRepository: dependencies.authRepository,
                rollRepository: dependencies.rollRepository,
                participantRepository: dependencies.participantRepository,
                inviteRepository: dependencies.inviteRepository,
                activeDevelopmentIdentityLabel: developmentIdentity?.displayName
            )
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
                case .loaded:
                    if let inviteToken = viewModel.visibleInviteToken {
                        inviteCard(token: inviteToken)
                    }

                    participantsCard
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    Task {
                        await viewModel.refresh()
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
            await viewModel.load()
        }
        .onDisappear {
            copyToastTask?.cancel()
        }
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
                        await viewModel.refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
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
}
