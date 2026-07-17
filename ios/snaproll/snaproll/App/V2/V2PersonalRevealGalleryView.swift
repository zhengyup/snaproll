import SwiftUI

struct V2PersonalRevealGalleryView: View {
    @StateObject private var viewModel: V2PersonalRevealGalleryViewModel
    @State private var selectedIndex: Int?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

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
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.82))
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
                .foregroundStyle(.white)

            Text(viewModel.filmLabel)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))
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
                .foregroundStyle(.black)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.94, green: 0.76, blue: 0.13))
                )
                .padding(.horizontal, 20)
            }

            LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    V2GalleryThumbnail(
                        item: item,
                        placeholderText: "Original unavailable",
                        showsDiagnostics: viewModel.shouldShowDiagnostics,
                        diagnostics: diagnostics(for: item)
                    ) {
                        selectedIndex = index
                    }
                }
            }
            .padding(.horizontal, 20)
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
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.72))

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
                .fill(.white.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
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
