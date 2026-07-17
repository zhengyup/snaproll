import SwiftUI

struct V2PersonalRevealGalleryView: View {
    @StateObject private var viewModel: V2PersonalRevealGalleryViewModel
    @State private var selectedIndex: Int?

    init(
        rollID: UUID,
        dependencies: V2DependencyContainer
    ) {
        _viewModel = StateObject(
            wrappedValue: V2PersonalRevealGalleryViewModel(
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

                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading revealed gallery")
                        .tint(Color(red: 0.88, green: 0.32, blue: 0.05))
                        .foregroundStyle(Color(red: 0.42, green: 0.35, blue: 0.29))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                case .failed(let message):
                    failedCard(message: message)
                case .loaded:
                    galleryGrid
                }
            }
            .padding(.vertical, 20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.985, blue: 0.955),
                    Color(red: 0.965, green: 0.925, blue: 0.875)
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
                        await viewModel.load()
                    }
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .fullScreenCover(item: selectedFullscreenItem) { selectedItem in
            V2GalleryFullscreenViewer(
                title: viewModel.title,
                filmLabel: viewModel.filmLabel,
                items: viewModel.items.map { $0 as any V2GalleryDisplayItem },
                selectedIndex: selectedItem.index,
                participantName: nil,
                onDismiss: {
                    selectedIndex = nil
                }
            )
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.title)
                .font(.title.weight(.semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.09))

            Text(viewModel.filmLabel)
                .font(.headline)
                .foregroundStyle(Color(red: 0.50, green: 0.42, blue: 0.34))
        }
        .padding(.horizontal, 20)
    }

    private var galleryGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.shouldShowDiagnostics && viewModel.hasRecoverableRenderFailures {
                Button {
                    Task {
                        await viewModel.retryRendering()
                    }
                } label: {
                    Text("Retry Rendering")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.88, green: 0.32, blue: 0.05))
                )
                .padding(.horizontal, 20)
            }

            VStack(spacing: 18) {
                V2GalleryAdaptiveRows(
                    items: viewModel.items,
                    placeholderText: "Original unavailable",
                    showsDiagnostics: viewModel.shouldShowDiagnostics,
                    diagnostics: diagnostics(for:)
                ) { index in
                    selectedIndex = index
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.58))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.045), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.06), radius: 22, x: 0, y: 10)
            )
            .padding(.horizontal, 16)
        }
    }

    private var selectedFullscreenItem: Binding<V2GalleryFullscreenSelection?> {
        Binding(
            get: {
                guard let selectedIndex else {
                    return nil
                }

                return V2GalleryFullscreenSelection(index: selectedIndex)
            },
            set: { selection in
                selectedIndex = selection?.index
            }
        )
    }

    private func diagnostics(for item: V2PersonalRevealGalleryViewModel.GalleryItem) -> [V2GalleryDiagnosticLine] {
        var lines = [
            V2GalleryDiagnosticLine(title: "Render seed", value: item.renderSeed),
            V2GalleryDiagnosticLine(title: "Sync state", value: item.syncState.rawValue),
            V2GalleryDiagnosticLine(title: "Source", value: item.renderingSource.rawValue),
            V2GalleryDiagnosticLine(title: "Original", value: item.localOriginalAvailable ? "Available" : "Missing"),
            V2GalleryDiagnosticLine(title: "Dimensions", value: "\(Int(item.pixelWidth)) x \(Int(item.pixelHeight))")
        ]

        if let duration = item.renderDurationMilliseconds {
            lines.append(V2GalleryDiagnosticLine(title: "Render time", value: String(format: "%.1f ms", duration)))
        }

        if let localOriginalPath = item.localOriginalPath {
            lines.append(V2GalleryDiagnosticLine(title: "Local path", value: localOriginalPath))
        }

        if let renderError = item.renderError {
            lines.append(V2GalleryDiagnosticLine(title: "Render error", value: renderError, isError: true))
        }

        return lines
    }

    private func failedCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unable to load gallery")
                .font(.headline)
                .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.09))

            Text(message)
                .font(.footnote)
                .foregroundStyle(Color(red: 0.42, green: 0.35, blue: 0.29))

            Button("Retry") {
                Task {
                    await viewModel.load()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.black.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 20)
    }

    private func diagnosticsLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))

            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
        }
    }
}
