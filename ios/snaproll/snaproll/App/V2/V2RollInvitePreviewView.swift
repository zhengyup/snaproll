import SwiftUI

struct V2RollInvitePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: V2RollInvitePreviewViewModel
    private let onDismissInvite: () -> Void
    private let onJoined: (UUID) -> Void

    init(
        invite: RollInviteLink,
        dependencies: V2DependencyContainer,
        onDismissInvite: @escaping () -> Void,
        onJoined: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: V2RollInvitePreviewViewModel(
                invite: invite,
                invitePreviewRepository: dependencies.invitePreviewRepository,
                participantRepository: dependencies.participantRepository
            )
        )
        self.onDismissInvite = onDismissInvite
        self.onJoined = onJoined
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                switch viewModel.state {
                case .idle, .loading:
                    Spacer()
                    ProgressView("Loading invitation")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                    Spacer()
                case .failed(let message):
                    inviteCard {
                        Text("Invitation Unavailable")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(message)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.72))

                        Button("Try Again") {
                            Task {
                                await viewModel.retry()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                case .loaded(let preview):
                    inviteCard {
                        Text("Snaproll Invite")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(red: 0.94, green: 0.76, blue: 0.13))
                            .textCase(.uppercase)
                            .tracking(1.8)

                        Text(preview.title)
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(.white)

                        if let creatorDisplayName = preview.creatorDisplayName {
                            Text("\(creatorDisplayName) invited you to join this shared roll.")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.72))
                        } else {
                            Text("You were invited to join this shared roll.")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        HStack(spacing: 12) {
                            stat("\(preview.participantCount)/\(preview.participantCap)", "People")
                            stat("\(preview.exposuresPerParticipant)", "Exposures")
                            stat(statusLabel(preview), "Status")
                        }

                        if !preview.isAcceptingParticipants {
                            Text("This roll is no longer accepting participants.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.orange.opacity(0.9))
                        }

                        if let joinErrorMessage = viewModel.joinErrorMessage {
                            Text(joinErrorMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red.opacity(0.88))
                        }

                        Button {
                            Task {
                                if let rollID = await viewModel.join() {
                                    onJoined(rollID)
                                    dismiss()
                                }
                            }
                        } label: {
                            if viewModel.isJoining {
                                ProgressView()
                                    .tint(.black)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Join Roll")
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
                        .disabled(viewModel.isJoining || !preview.isAcceptingParticipants)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .navigationTitle("Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        onDismissInvite()
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
        }
    }

    private func inviteCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.white.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)

            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.18))
        )
    }

    private func statusLabel(_ preview: RollInvitePreview) -> String {
        if preview.isAcceptingParticipants {
            return "Open"
        }

        return preview.status.rawValue.replacingOccurrences(of: "_", with: " ")
    }
}
