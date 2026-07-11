import SwiftUI

struct V2SharedRevealGalleryView: View {
    @StateObject private var viewModel: V2SharedRevealGalleryViewModel

    init(
        rollID: UUID,
        dependencies: V2DependencyContainer
    ) {
        _viewModel = StateObject(
            wrappedValue: V2SharedRevealGalleryViewModel(
                rollID: rollID,
                authRepository: dependencies.authRepository,
                rollRepository: dependencies.rollRepository,
                participantRepository: dependencies.participantRepository,
                exposureRepository: dependencies.exposureRepository,
                exposureMirrorStore: dependencies.exposureMirrorStore,
                storageRepository: dependencies.exposureAssetStorageRepository
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading shared gallery")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                case .failed(let message):
                    failedCard(message: message)
                case .loaded:
                    sectionsView
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

    private var sectionsView: some View {
        VStack(alignment: .leading, spacing: 18) {
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

            ForEach(viewModel.sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(section.displayName)
                            .font(.headline)
                            .foregroundStyle(.white)

                        if section.isCurrentUser {
                            capsuleLabel("You")
                        }

                        if section.isCreator {
                            capsuleLabel("Creator")
                        }
                    }

                    Text(section.status.rawValue.replacingOccurrences(of: "_", with: " "))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.66))

                    ForEach(section.items) { item in
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
                                        Text("Image unavailable")
                                            .font(.footnote)
                                    }
                                    .foregroundStyle(.white.opacity(0.65))
                                    .padding(24)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Exposure \(item.exposureNumber)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)

                                Text(viewModel.title)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.82))
                            }

                            if viewModel.shouldShowDiagnostics {
                                VStack(alignment: .leading, spacing: 3) {
                                    diagnosticsLine("Render seed", item.renderSeed)
                                    diagnosticsLine("Sync state", item.syncState.rawValue)
                                    diagnosticsLine("Source", item.renderingSource.rawValue)
                                    diagnosticsLine("Original", item.localOriginalAvailable ? "Available" : "Missing")

                                    if let cloudStoragePath = item.cloudStoragePath {
                                        diagnosticsLine("Cloud path", cloudStoragePath)
                                    }

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
                                .fill(.white.opacity(0.06))
                        )
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
            Text("Unable to load shared gallery")
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

    private func capsuleLabel(_ label: String) -> some View {
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
}
