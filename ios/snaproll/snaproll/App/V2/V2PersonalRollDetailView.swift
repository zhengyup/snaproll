import SwiftUI

struct V2PersonalRollDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: V2PersonalRollDetailViewModel
    @State private var isShowingCaptureView = false
    private let dependencies: V2DependencyContainer

    init(
        rollID: UUID,
        dependencies: V2DependencyContainer,
        developmentIdentity: DevelopmentAuthIdentity? = nil
    ) {
        self.dependencies = dependencies
        let uploadPipeline = V2ExposureUploadPipeline(
            exposureMirrorStore: dependencies.exposureMirrorStore,
            photoStorageService: dependencies.photoStorageService,
            storageRepository: dependencies.exposureAssetStorageRepository
        )
        let metadataPipeline = V2ExposureMetadataCompletionPipeline(
            exposureMirrorStore: dependencies.exposureMirrorStore,
            exposureRepository: dependencies.exposureRepository
        )
        let syncRunner = V2ExposureSyncRunner(
            exposureMirrorStore: dependencies.exposureMirrorStore,
            uploadStage: uploadPipeline,
            metadataStage: metadataPipeline
        )
        _viewModel = StateObject(
            wrappedValue: V2PersonalRollDetailViewModel(
                rollID: rollID,
                rollRepository: dependencies.rollRepository,
                exposureRepository: dependencies.exposureRepository,
                exposureMirrorStore: dependencies.exposureMirrorStore,
                photoStorageService: dependencies.photoStorageService,
                syncRunner: syncRunner,
                activeDevelopmentIdentityLabel: developmentIdentity?.displayName
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
        .navigationDestination(isPresented: $isShowingCaptureView) {
            if let roll = viewModel.roll {
                V2CaptureView(
                    roll: roll,
                    dependencies: dependencies,
                    onCaptureCompleted: {
                        await viewModel.handleCaptureSessionEnded()
                    }
                )
            }
        }
        .task {
            await viewModel.handleAppear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            Task {
                await viewModel.handleSceneBecameActive()
            }
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

            if let syncStatus = viewModel.userFacingSyncStatus {
                Text(syncStatus)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
            }

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

            if viewModel.shouldShowCaptureAction {
                Button {
                    isShowingCaptureView = true
                } label: {
                    Text("Capture Next Exposure")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
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

            if viewModel.shouldShowProcessPendingAction {
                Button {
                    Task {
                        await viewModel.processPendingExposures()
                    }
                } label: {
                    if viewModel.isSynchronizing {
                        ProgressView()
                            .tint(.black)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Process Pending Exposures")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.94, green: 0.76, blue: 0.13))
                )
                .disabled(viewModel.isSynchronizing)
            }

            if viewModel.shouldShowRetryFailedAction {
                Button {
                    Task {
                        await viewModel.retryFailedSynchronization()
                    }
                } label: {
                    if viewModel.isSynchronizing {
                        ProgressView()
                            .tint(.black)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Retry Failed Sync")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
                .disabled(viewModel.isSynchronizing)
            }

            if viewModel.shouldShowForceRefreshAction {
                Button {
                    Task {
                        await viewModel.forceRefresh()
                    }
                } label: {
                    Text("Force Refresh")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black.opacity(0.18))
                )
            }

            if let lastSyncMessage = viewModel.lastSyncMessage {
                Text(lastSyncMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
            }

            if let summary = viewModel.diagnosticsSummary {
                VStack(alignment: .leading, spacing: 6) {
                    if let activeIdentityLabel = summary.activeIdentityLabel {
                        diagnosticsSummaryLine(title: "Identity", value: activeIdentityLabel)
                    }

                    diagnosticsSummaryLine(title: "Roll ID", value: summary.rollID.uuidString)
                    diagnosticsSummaryLine(
                        title: "Status",
                        value: summary.rollStatus.rawValue.replacingOccurrences(of: "_", with: " ")
                    )
                    diagnosticsSummaryLine(title: "Captured", value: "\(summary.capturedCount)")
                    diagnosticsSummaryLine(title: "Remaining", value: "\(summary.remainingCount)")
                    diagnosticsSummaryLine(title: "Pending", value: "\(summary.pendingCount)")
                    diagnosticsSummaryLine(title: "Failed", value: "\(summary.failedCount)")
                    diagnosticsSummaryLine(title: "Synchronizing", value: summary.isSynchronizing ? "Yes" : "No")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black.opacity(0.18))
                )
            }

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

                        Text(row.localFileExists ? "Local file exists" : "No local file")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))

                        if row.uploadJPEGPath != nil {
                            Text(row.localUploadFileExists ? "Upload JPEG exists" : "Upload JPEG missing")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        if let localOriginalPath = row.localOriginalPath {
                            Text(localOriginalPath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.white.opacity(0.58))
                                .textSelection(.enabled)
                        }

                        if let uploadJPEGPath = row.uploadJPEGPath {
                            Text(uploadJPEGPath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.white.opacity(0.58))
                                .textSelection(.enabled)
                        }

                        if let cloudStoragePath = row.cloudStoragePath {
                            Text(cloudStoragePath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.white.opacity(0.58))
                                .textSelection(.enabled)
                        }

                        if let captureTimestamp = row.captureTimestamp {
                            Text(captureTimestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        if let uploadedAt = row.uploadedAt {
                            Text(uploadedAt.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        if let lastError = row.lastError {
                            Text(lastError)
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.82))
                        }

                        Text(row.id.uuidString)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.58))
                            .textSelection(.enabled)

                        Text("Render seed: \(row.renderSeed)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.58))
                            .textSelection(.enabled)

                        if row.localFileExists, let localOriginalPath = row.localOriginalPath,
                           let image = dependencies.photoStorageService.loadImage(at: localOriginalPath) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 92, height: 124)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
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

    private func diagnosticsSummaryLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.88))
                .textSelection(.enabled)
        }
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
