import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                SnaprollScreenBackground()

                if viewModel.rolls.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .onAppear {
                viewModel.reload()
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    ForEach(Array(viewModel.rolls.enumerated()), id: \.element.id) { index, roll in
                        NavigationLink {
                            RollView(
                                roll: roll,
                                onRollUpdated: { updatedRoll in
                                    viewModel.updateRoll(updatedRoll)
                                },
                                onDelete: {
                                    viewModel.deleteRoll(id: roll.id)
                                }
                            )
                        } label: {
                            RollListCard(
                                roll: roll,
                                state: cardState(for: roll, index: index)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }

            HomeTabBar()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(headerMonth)
                        .font(.system(size: 14, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(AppTheme.primaryAction)

                    Text("My Rolls")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .italic()
                        .foregroundStyle(AppTheme.creamText)

                    Text("\(viewModel.activeRollCount) active · \(viewModel.rolls.count) total")
                        .font(.title3)
                        .foregroundStyle(AppTheme.softText)
                }

                Spacer()

                NavigationLink {
                    createRollView
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.primaryAction)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(alignment: .leading, spacing: 14) {
                    Text("Start your first roll")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .italic()
                        .foregroundStyle(AppTheme.creamText)

                    Text("Name it, choose a film, and let the memories stay hidden until the roll is full.")
                        .font(.title3)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .background(SnaprollPanelBackground(cornerRadius: 24))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            HomeTabBar()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    private var createRollView: some View {
        CreateRollView { name, film, shotLimit in
            viewModel.createRoll(
                name: name,
                film: film,
                shotLimit: shotLimit
            )
        }
    }

    private var headerMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: viewModel.activeRoll?.createdAt ?? .now).uppercased()
    }

    private func cardState(for roll: Roll, index: Int) -> RollCardState {
        if roll.isRevealed {
            return .revealed
        }
        if roll.isCompleted {
            return .ready
        }
        if index == 0 {
            return .shooting
        }
        return .developing
    }
}

private enum RollCardState {
    case shooting
    case developing
    case ready
    case revealed

    var title: String {
        switch self {
        case .shooting:
            return "Shooting"
        case .developing:
            return "Developing"
        case .ready:
            return "Ready"
        case .revealed:
            return "Revealed"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .shooting:
            return AppTheme.primaryAction.opacity(0.22)
        case .developing:
            return Color.white.opacity(0.10)
        case .ready:
            return Color(red: 0.15, green: 0.45, blue: 0.26)
        case .revealed:
            return Color.white.opacity(0.10)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .shooting:
            return AppTheme.primaryAction
        case .developing:
            return AppTheme.mutedText
        case .ready:
            return Color(red: 0.39, green: 0.93, blue: 0.58)
        case .revealed:
            return AppTheme.creamText
        }
    }
}

private struct RollListCard: View {
    let roll: Roll
    let state: RollCardState

    var body: some View {
        HStack(spacing: 16) {
            FilmCanisterView(film: roll.film, size: .small)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(roll.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.creamText)

                        Text(roll.film.displayName)
                            .font(.title3)
                            .foregroundStyle(AppTheme.softText)
                    }

                    Spacer()

                    Text(state.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(state.foregroundColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(state.backgroundColor)
                        .clipShape(Capsule())
                }

                HStack {
                    Spacer()

                    Text(progressText)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.card.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 14, y: 8)
    }

    private var progressText: String {
        roll.captureProgressText.replacingOccurrences(of: " ", with: "")
    }
}

private struct HomeTabBar: View {
    var body: some View {
        HStack {
            Spacer()
            HomeTabItem(symbol: "square.on.square", isSelected: true)
            Spacer()
            HomeTabItem(symbol: "photo.on.rectangle", isSelected: false)
            Spacer()
            HomeTabItem(symbol: "person", isSelected: false)
            Spacer()
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.surface.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct HomeTabItem: View {
    let symbol: String
    let isSelected: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(isSelected ? AppTheme.primaryAction : AppTheme.softText)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
