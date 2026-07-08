import SwiftUI

struct V2PersonalRollDetailView: View {
    @StateObject private var viewModel: V2PersonalRollDetailViewModel

    init(
        rollID: UUID,
        dependencies: V2DependencyContainer
    ) {
        _viewModel = StateObject(
            wrappedValue: V2PersonalRollDetailViewModel(
                rollID: rollID,
                rollRepository: dependencies.rollRepository,
                exposureRepository: dependencies.exposureRepository,
                exposureMirrorStore: dependencies.exposureMirrorStore
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                progressCard

                if viewModel.shouldShowDiagnostics {
                    diagnosticsCard
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
        .navigationTitle(viewModel.roll?.title ?? "Roll")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.roll?.title ?? "Loading Roll")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)

            Text(viewModel.filmLabel)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))

            Text(viewModel.statusLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))

            if viewModel.shouldShowStartRoll {
                Button {
                    Task {
                        await viewModel.startRoll()
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

            if case .failed(let message) = viewModel.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))

            HStack(spacing: 16) {
                progressMetric(title: "Total", value: "\(viewModel.totalExposures)")
                progressMetric(title: "Captured", value: "\(viewModel.capturedExposures)")
                progressMetric(title: "Remaining", value: "\(viewModel.remainingExposures)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Development Diagnostics")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))

            if viewModel.diagnosticsRows.isEmpty {
                Text("No mirrored exposures yet.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(viewModel.diagnosticsRows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exposure \(row.exposureNumber)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(row.syncState.rawValue)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))

                        Text(row.id.uuidString)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.58))
                            .textSelection(.enabled)

                        Text("Render seed: \(row.renderSeed)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.58))
                            .textSelection(.enabled)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.black.opacity(0.14))
                    )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func progressMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.white.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }
}
