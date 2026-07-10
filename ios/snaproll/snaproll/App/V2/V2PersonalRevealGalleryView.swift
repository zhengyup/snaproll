import SwiftUI

struct V2PersonalRevealGalleryView: View {
    @StateObject private var viewModel: V2PersonalRevealGalleryViewModel

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

            ForEach(viewModel.items) { item in
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.black.opacity(0.20))

                        if let image = item.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(10)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.title2)
                                Text("Original unavailable")
                                    .font(.footnote)
                            }
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(24)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exposure \(item.exposureNumber)")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(viewModel.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))

                        Text(viewModel.filmLabel)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.64))
                    }

                    if viewModel.shouldShowDiagnostics {
                        VStack(alignment: .leading, spacing: 3) {
                            diagnosticsLine("Render seed", item.renderSeed)
                            diagnosticsLine("Sync state", item.syncState.rawValue)
                            diagnosticsLine("Source", item.renderingSource.rawValue)
                            diagnosticsLine("Original", item.localOriginalAvailable ? "Available" : "Missing")

                            if let duration = item.renderDurationMilliseconds {
                                diagnosticsLine("Render time", String(format: "%.1f ms", duration))
                            }

                            if let localOriginalPath = item.localOriginalPath {
                                diagnosticsLine("Local path", localOriginalPath)
                            }

                            if let renderError = item.renderError {
                                Text(renderError)
                                    .font(.caption2)
                                    .foregroundStyle(.red.opacity(0.82))
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                )
                .padding(.horizontal, 20)
            }
        }
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
