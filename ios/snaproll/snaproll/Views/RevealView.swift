import SwiftUI

struct RevealView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RevealViewModel

    init(
        roll: Roll,
        localStorageService: LocalStorageService? = nil,
        photoStorageService: PhotoStorageService? = nil,
        onRollUpdated: ((Roll) -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: RevealViewModel(
                roll: roll,
                localStorageService: localStorageService,
                photoStorageService: photoStorageService,
                onRollUpdated: onRollUpdated
            )
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                topBar

                if viewModel.showsGallery {
                    revealedContent
                        .transition(.opacity)
                } else {
                    sealedContent
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .background(SnaprollScreenBackground())
        .onAppear {
            viewModel.handleAppear()
        }
        .snaprollScreenNavigation()
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAction)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var sealedContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("COMPLETED")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(AppTheme.primaryAction)

                Text(viewModel.roll.name)
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(AppTheme.creamText)

                Text("Every exposure has been used. When you're ready, open the roll and revisit each memory in order.")
                    .font(.title3)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 18) {
                FilmCanisterView(film: viewModel.roll.film, size: .large)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    Text(viewModel.roll.captureProgressText)
                        .font(.system(size: 52, weight: .medium, design: .serif))
                        .foregroundStyle(AppTheme.creamText)

                    Text("Memories waiting inside")
                        .font(.title3)
                        .foregroundStyle(AppTheme.softText)
                }
            }
            .frame(maxWidth: .infinity)

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.softText)
            }

            Button {
                viewModel.revealRoll()
            } label: {
                HStack {
                    if viewModel.isRevealing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.black.opacity(0.85))
                    }

                    Text(viewModel.isRevealing ? "Opening Roll" : "Reveal Roll")
                        .font(.headline)
                }
                .foregroundStyle(Color.black.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.primaryAction)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRevealing)
        }
    }

    private var revealedContent: some View {
        GalleryView(
            roll: viewModel.roll,
            photoItems: viewModel.photoItems,
            isLoading: viewModel.isLoading
        )
    }
}

struct RevealView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RevealView(roll: Roll.placeholder.markingRevealed())
        }
    }
}
