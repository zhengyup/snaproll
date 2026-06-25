import SwiftUI

struct RollView: View {
    let onRollUpdated: ((Roll) -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var roll: Roll
    @State private var showingDeleteConfirmation = false

    init(roll: Roll, onRollUpdated: ((Roll) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.onRollUpdated = onRollUpdated
        self.onDelete = onDelete
        _roll = State(initialValue: roll)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                topBar
                header
                hero
                metadataCard
                primaryButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .background(SnaprollScreenBackground())
        .confirmationDialog(
            "Delete this roll?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Roll", role: .destructive) {
                onDelete?()
                dismiss()
            }

            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text("This will remove the roll from local storage on this device.")
        }
        .snaprollScreenNavigation()
        .snaprollPreferredOrientations(.portrait)
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

            if onDelete != nil {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.primaryAction)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(statusTitle)
                .font(.system(size: 14, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppTheme.primaryAction)

            Text(roll.name)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .italic()
                .foregroundStyle(AppTheme.creamText)

            Text(roll.film.displayName)
                .font(.title3)
                .foregroundStyle(AppTheme.softText)
        }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            FilmCanisterView(film: roll.film, size: .large)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            VStack(spacing: 10) {
                Text(progressText)
                    .font(.system(size: 52, weight: .medium, design: .serif))
                    .foregroundStyle(AppTheme.creamText)

                Text("Photos taken")
                    .font(.title3)
                    .foregroundStyle(AppTheme.softText)
            }

            ProgressView(value: roll.progressValue)
                .tint(AppTheme.primaryAction)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
        }
        .frame(maxWidth: .infinity)
    }

    private var metadataCard: some View {
        VStack(spacing: 0) {
            DetailRow(
                symbol: "camera",
                title: "Film",
                value: roll.film.displayName
            )

            Divider()
                .overlay(Color.white.opacity(0.06))

            DetailRow(
                symbol: "photo",
                title: "Photos",
                value: "\(capturedCount) of \(roll.shotLimit)"
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(SnaprollPanelBackground(cornerRadius: 18))
    }

    private var primaryButton: some View {
        Group {
            if roll.isCompleted || roll.isRevealed {
                NavigationLink {
                    RevealView(
                        roll: roll,
                        onRollUpdated: { updatedRoll in
                            roll = updatedRoll
                            onRollUpdated?(updatedRoll)
                        }
                    )
                } label: {
                    actionButtonLabel(
                        title: revealButtonTitle,
                        foreground: Color.black.opacity(0.9),
                        background: AppTheme.primaryAction
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    CameraView(
                        roll: roll,
                        onRollUpdated: { updatedRoll in
                            roll = updatedRoll
                            onRollUpdated?(updatedRoll)
                        }
                    )
                } label: {
                    actionButtonLabel(
                        title: "Continue Shooting",
                        foreground: AppTheme.primaryAction,
                        background: Color.white.opacity(0.05)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionButtonLabel(title: String, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(background)
            )
    }

    private var capturedCount: Int {
        roll.capturedMemories
    }

    private var progressText: String {
        "\(capturedCount) / \(roll.shotLimit)"
    }

    private var statusTitle: String {
        if roll.isRevealed {
            return "REVEALED"
        }

        if roll.isCompleted {
            return "READY"
        }

        return "SHOOTING"
    }

    private var revealButtonTitle: String {
        roll.isRevealed ? "View Roll" : "Reveal Roll"
    }
}

private struct DetailRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 20)

            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(AppTheme.creamText)

            Spacer()

            Text(value)
                .font(.title3)
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(.vertical, 14)
    }
}

struct RollView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RollView(roll: .placeholder)
        }
    }
}
