import SwiftUI

struct V2SharedRevealGalleryView: View {
    @StateObject private var viewModel: V2SharedRevealGalleryViewModel
    @State private var selectedSectionID: UUID?
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
        .fullScreenCover(isPresented: isShowingFullscreenViewer) {
            if let selection = fullscreenSelection {
                V2GalleryFullscreenViewer(
                    title: viewModel.title,
                    filmLabel: viewModel.filmLabel,
                    items: selection.section.items.map { $0 as any V2GalleryDisplayItem },
                    selectedIndex: selection.index,
                    participantName: selection.section.displayName,
                    onDismiss: {
                        selectedSectionID = nil
                        selectedIndex = nil
                    }
                )
            }
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

                    LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            V2GalleryThumbnail(
                                item: item,
                                placeholderText: "Image unavailable",
                                showsDiagnostics: viewModel.shouldShowDiagnostics,
                                diagnostics: diagnostics(for: item)
                            ) {
                                selectedSectionID = section.id
                                selectedIndex = index
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

    private var isShowingFullscreenViewer: Binding<Bool> {
        Binding(
            get: {
                selectedSectionID != nil && selectedIndex != nil
            },
            set: { isPresented in
                if !isPresented {
                    selectedSectionID = nil
                    selectedIndex = nil
                }
            }
        )
    }

    private var fullscreenSelection: (section: V2SharedRevealGalleryViewModel.ParticipantSection, index: Int)? {
        guard let selectedSectionID,
              let selectedIndex,
              let section = viewModel.sections.first(where: { $0.id == selectedSectionID }),
              section.items.indices.contains(selectedIndex) else {
            return nil
        }

        return (section, selectedIndex)
    }

    private func diagnostics(for item: V2SharedRevealGalleryViewModel.GalleryItem) -> [V2GalleryDiagnosticLine] {
        var lines = [
            V2GalleryDiagnosticLine(title: "Render seed", value: item.renderSeed),
            V2GalleryDiagnosticLine(title: "Sync state", value: item.syncState.rawValue),
            V2GalleryDiagnosticLine(title: "Source", value: item.renderingSource.rawValue),
            V2GalleryDiagnosticLine(title: "Original", value: item.localOriginalAvailable ? "Available" : "Missing"),
            V2GalleryDiagnosticLine(title: "Dimensions", value: "\(Int(item.pixelWidth)) x \(Int(item.pixelHeight))")
        ]

        if let cloudStoragePath = item.cloudStoragePath {
            lines.append(V2GalleryDiagnosticLine(title: "Cloud path", value: cloudStoragePath))
        }

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
