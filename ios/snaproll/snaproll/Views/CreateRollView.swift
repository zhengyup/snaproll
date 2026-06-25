import SwiftUI

struct CreateRollView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateRollViewModel()

    let onCreateRoll: (_ name: String, _ film: FilmStock, _ shotLimit: Int) -> Roll

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                topBar
                header
                nameField
                filmPicker
                shotLimitPicker
                createButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .background(SnaprollScreenBackground())
        .snaprollScreenNavigation()
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEW ROLL")
                .font(.system(size: 14, weight: .bold, design: .default))
                .tracking(2)
                .foregroundStyle(AppTheme.primaryAction)

            Text("Create Roll")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .italic()
                .foregroundStyle(AppTheme.creamText)

            Text("Give your roll a name and choose your film.")
                .font(.title3)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Roll Name")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.softText)

            HStack(spacing: 12) {
                TextField("Summer Walks", text: $viewModel.name)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .foregroundStyle(AppTheme.creamText)

                if !viewModel.name.isEmpty {
                    Button {
                        viewModel.name = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.softText)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(SnaprollPanelBackground(cornerRadius: 18))
        }
    }

    private var filmPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHOOSE FILM")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(AppTheme.softText)

            ForEach(FilmStock.allCases) { film in
                Button {
                    viewModel.selectedFilm = film
                } label: {
                    HStack(spacing: 14) {
                        FilmCanisterView(film: film, size: .small)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(film.displayName)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(AppTheme.creamText)

                            Text(film.shortDescription)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.softText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Text(film.typeLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.softText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())

                        ZStack {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5)
                                .frame(width: 28, height: 28)

                            if film == viewModel.selectedFilm {
                                Circle()
                                    .fill(AppTheme.primaryAction)
                                    .frame(width: 28, height: 28)

                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.black.opacity(0.85))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.surfaceRaised.opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                film == viewModel.selectedFilm ? AppTheme.primaryAction.opacity(0.55) : AppTheme.border,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shotLimitPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PHOTOS")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(AppTheme.softText)

            HStack {
                Button {
                    viewModel.shotLimit = max(AppConfig.Rolls.minimumShotLimit, viewModel.shotLimit - 1)
                } label: {
                    stepperControl(symbol: "minus")
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(viewModel.shotLimit)")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.creamText)

                Spacer()

                Button {
                    viewModel.shotLimit = min(AppConfig.Rolls.maximumShotLimit, viewModel.shotLimit + 1)
                } label: {
                    stepperControl(symbol: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(SnaprollPanelBackground(cornerRadius: 18))
        }
    }

    private func stepperControl(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.creamText)
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var createButton: some View {
        Button {
            _ = onCreateRoll(
                viewModel.name,
                viewModel.selectedFilm,
                viewModel.shotLimit
            )
            dismiss()
        } label: {
            Text("Create Roll")
                .font(.headline)
                .foregroundStyle(Color.black.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(viewModel.canSave ? AppTheme.primaryAction : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSave)
        .padding(.top, 12)
    }
}

struct CreateRollView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CreateRollView { name, film, shotLimit in
                Roll(
                    id: UUID(),
                    name: name,
                    film: film,
                    shotLimit: shotLimit,
                    createdAt: .now
                )
            }
        }
    }
}
