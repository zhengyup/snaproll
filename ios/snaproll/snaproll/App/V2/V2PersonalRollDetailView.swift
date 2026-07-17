import SwiftUI

struct V2PersonalRollDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: V2PersonalRollDetailViewModel
    @StateObject private var synchronizer: V2SharedStateSynchronizer
    @State private var isShowingCaptureView = false
    @State private var isShowingGalleryView = false
    private let dependencies: V2DependencyContainer

    init(
        rollID: UUID,
        dependencies: V2DependencyContainer,
        developmentIdentity: DevelopmentAuthIdentity? = nil
    ) {
        self.dependencies = dependencies
        let viewModel = V2PersonalRollDetailViewModel(
            rollID: rollID,
            rollRepository: dependencies.rollRepository,
            authRepository: dependencies.authRepository,
            participantRepository: dependencies.participantRepository,
            exposureRepository: dependencies.exposureRepository,
            exposureMirrorStore: dependencies.exposureMirrorStore,
            photoStorageService: dependencies.photoStorageService,
            syncRunner: dependencies.exposureSyncRunner,
            pendingRecoveryCoordinator: dependencies.pendingExposureRecoveryCoordinator,
            activeDevelopmentIdentityLabel: developmentIdentity?.displayName
        )
        _viewModel = StateObject(wrappedValue: viewModel)
        _synchronizer = StateObject(
            wrappedValue: V2SharedStateSynchronizer(rollID: rollID) { [weak viewModel] in
                guard let viewModel else {
                    return nil
                }

                return try await viewModel.refreshForSharedStateSynchronization()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                topChrome
                headerCard
                progressCard

                if viewModel.shouldShowParticipantProgress {
                    participantProgressCard
                }

                detailRowsCard
                tipCard

                if viewModel.shouldShowDiagnostics {
                    diagnosticsCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(detailBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $isShowingCaptureView) {
            if let roll = viewModel.roll {
                V2CaptureView(
                    roll: roll,
                    currentParticipantID: viewModel.currentParticipant?.id,
                    currentParticipantDisplayName: viewModel.currentParticipantDisplayName,
                    dependencies: dependencies,
                    onCaptureCompleted: {
                        await viewModel.handleCaptureSessionEnded()
                        await synchronizer.refreshNow()
                    }
                )
            }
        }
        .navigationDestination(isPresented: $isShowingGalleryView) {
            if viewModel.roll?.type == .shared {
                V2SharedRevealGalleryView(
                    rollID: viewModel.rollID,
                    dependencies: dependencies
                )
            } else {
                V2PersonalRevealGalleryView(
                    rollID: viewModel.rollID,
                    dependencies: dependencies
                )
            }
        }
        .task {
            await viewModel.handleAppear()
            if viewModel.isSharedRoll {
                synchronizer.seedLatestKnownState(viewModel.roll?.status)
                await synchronizer.start()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                if newPhase == .active {
                    await viewModel.handleSceneBecameActive()
                    if viewModel.isSharedRoll {
                        await synchronizer.handleSceneActivity(isActive: true)
                    }
                } else {
                    await synchronizer.handleSceneActivity(isActive: false)
                }
            }
        }
        .onDisappear {
            Task {
                await synchronizer.stop()
            }
        }
    }

    private var topChrome: some View {
        VStack(spacing: 18) {
            HStack {
                Text("snaproll")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(detailInk)

                Spacer()

                Image(systemName: "gift")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(detailInk)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.56, blue: 0.18),
                                Color(red: 0.13, green: 0.32, blue: 0.38)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Circle().strokeBorder(.white, lineWidth: 2)
                    }
            }

            ZStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(detailInk)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white.opacity(0.72)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {} label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(detailInk)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white.opacity(0.72)))
                    }
                    .buttonStyle(.plain)
                }

                Text(viewModel.roll?.title ?? "Roll")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(detailInk)
                    .lineLimit(1)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 22) {
                Image(spriteName)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: 10) {
                    feelPill

                    Text(viewModel.roll?.title ?? "Loading Roll")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(detailInk)
                        .lineLimit(2)

                    Text(feelDescription)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(detailMuted)
                        .lineSpacing(3)
                }
            }

            primaryActionButton

            if case .failed(let message) = viewModel.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.85))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(spriteName)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                Text("Progress")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(detailInk)
            }

            HStack(spacing: 0) {
                progressMetric(title: "Total", value: "\(viewModel.totalExposures)")
                metricDivider
                progressMetric(title: "Captured", value: "\(viewModel.capturedExposures)")
                metricDivider
                progressMetric(title: "Remaining", value: "\(viewModel.remainingExposures)")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var detailRowsCard: some View {
        VStack(spacing: 0) {
            detailRow(
                icon: "calendar",
                title: "Created",
                value: createdDateLabel
            )

            rowDivider

            detailRow(
                icon: "person.2",
                title: "Participants",
                value: participantsLabel
            )

            rowDivider

            detailRow(
                icon: "lock",
                title: "Privacy",
                value: viewModel.isSharedRoll ? "Only invited people can join" : "Only you"
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 6) {
                Text("Tip")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)

                Text("Once all exposures are captured, your roll will be developed and ready to reveal.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(detailMuted)
                    .lineSpacing(3)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var participantProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participant Progress")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))

            ForEach(viewModel.participantProgressRows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(row.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if row.isCurrentUser {
                            capsuleLabel("You")
                        }

                        if row.isCreator {
                            capsuleLabel("Creator")
                        }
                    }

                    Text(row.status.rawValue.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black.opacity(0.14))
                )
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
                        if viewModel.isSharedRoll {
                            await synchronizer.refreshNow()
                        }
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
                        if viewModel.isSharedRoll {
                            await synchronizer.refreshNow()
                        }
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
                        if viewModel.isSharedRoll {
                            await synchronizer.refreshNow()
                        } else {
                            await viewModel.forceRefresh()
                        }
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

                    if viewModel.isSharedRoll {
                        diagnosticsSummaryLine(title: "Polling active", value: synchronizer.snapshot.isPollingActive ? "Yes" : "No")
                        diagnosticsSummaryLine(title: "Polling blocked", value: synchronizer.snapshot.isPollingBlocked ? "Yes" : "No")
                        diagnosticsSummaryLine(title: "Poll count", value: "\(synchronizer.snapshot.pollCount)")

                        if let currentIntervalSeconds = synchronizer.snapshot.currentIntervalSeconds {
                            diagnosticsSummaryLine(title: "Polling interval", value: String(format: "%.0f s", currentIntervalSeconds))
                        }

                        if let latestBackendState = synchronizer.snapshot.latestBackendState {
                            diagnosticsSummaryLine(
                                title: "Latest backend state",
                                value: latestBackendState.rawValue.replacingOccurrences(of: "_", with: " ")
                            )
                        }

                        if let lastRefreshAt = synchronizer.snapshot.lastRefreshAt {
                            diagnosticsSummaryLine(
                                title: "Last refresh",
                                value: lastRefreshAt.formatted(date: .abbreviated, time: .standard)
                            )
                        }

                        if let lastRefreshDurationMilliseconds = synchronizer.snapshot.lastRefreshDurationMilliseconds {
                            diagnosticsSummaryLine(
                                title: "Refresh duration",
                                value: String(format: "%.1f ms", lastRefreshDurationMilliseconds)
                            )
                        }

                        if let lastErrorMessage = synchronizer.snapshot.lastErrorMessage {
                            diagnosticsSummaryLine(title: "Last polling error", value: lastErrorMessage)
                        }
                    }
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

                        if let ownerUserID = row.ownerUserID {
                            Text("Owner: \(ownerUserID.uuidString)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.white.opacity(0.58))
                                .textSelection(.enabled)
                        }

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

                        if let recoveryFromState = row.recoveryFromState {
                            Text("Recovered from: \(recoveryFromState)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        if let recoveryToState = row.recoveryToState {
                            Text("Recovered to: \(recoveryToState)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        if let recoveryReason = row.recoveryReason {
                            Text(recoveryReason)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        if let lastRecoveredAt = row.lastRecoveredAt {
                            Text("Last recovery: \(lastRecoveredAt.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        if let lastError = row.lastError {
                            Text(lastError)
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.82))
                        }

                        if let recoveryError = row.recoveryError {
                            Text("Recovery error: \(recoveryError)")
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.82))
                        }

                        if let reconciliationRule = row.reconciliationRule {
                            Text("Reconciled: \(reconciliationRule)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        if let lastReconciledAt = row.lastReconciledAt {
                            Text("Last reconciliation: \(lastReconciledAt.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        if let reconciliationError = row.reconciliationError {
                            Text("Reconciliation error: \(reconciliationError)")
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
        .background(darkDiagnosticsBackground)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if viewModel.shouldShowStartRoll {
            Button {
                Task {
                    await viewModel.startRoll()
                    if viewModel.isSharedRoll {
                        await synchronizer.refreshNow()
                    }
                }
            } label: {
                if viewModel.isStartingRoll {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Start Roll", systemImage: "play.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.vertical, 17)
            .background(primaryButtonBackground)
            .disabled(viewModel.isStartingRoll)
        } else if viewModel.shouldShowCaptureAction {
            Button {
                isShowingCaptureView = true
            } label: {
                Label(
                    viewModel.isSharedRoll ? "Capture Your Next Exposure" : "Capture Next Exposure",
                    systemImage: "camera.fill"
                )
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.vertical, 17)
            .background(primaryButtonBackground)
        } else if viewModel.shouldShowRevealAction {
            Button {
                Task {
                    let didReveal = await viewModel.revealRoll()
                    if viewModel.isSharedRoll {
                        await synchronizer.refreshNow()
                    }
                    if didReveal {
                        isShowingGalleryView = true
                    }
                }
            } label: {
                if viewModel.isRevealingRoll {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Reveal Roll", systemImage: "sparkles")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.vertical, 17)
            .background(primaryButtonBackground)
            .disabled(viewModel.isRevealingRoll)
        } else if viewModel.shouldShowViewGalleryAction {
            Button {
                isShowingGalleryView = true
            } label: {
                Label("View Roll", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.vertical, 17)
            .background(primaryButtonBackground)
        }
    }

    private var feelPill: some View {
        HStack(spacing: 5) {
            Image(systemName: isWarmRoll ? "sun.max" : "snowflake")
                .font(.system(size: 12, weight: .semibold))

            Text(viewModel.filmLabel)
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .foregroundStyle(accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(accentColor.opacity(0.1))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(accentColor.opacity(0.16), lineWidth: 1)
                }
        )
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(detailInk)

                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(detailMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.68, green: 0.62, blue: 0.56))
        }
        .padding(.vertical, 12)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color(red: 0.93, green: 0.86, blue: 0.78))
            .frame(width: 1, height: 56)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(red: 0.93, green: 0.86, blue: 0.78))
            .frame(height: 1)
            .padding(.leading, 48)
    }

    private var primaryButtonBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isWarmRoll
                        ? [Color(red: 1.0, green: 0.39, blue: 0.02), Color(red: 0.9, green: 0.24, blue: 0.02)]
                        : [Color(red: 0.2, green: 0.62, blue: 1.0), Color(red: 0.03, green: 0.42, blue: 0.92)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: accentColor.opacity(0.22), radius: 12, y: 7)
    }

    private var detailBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.985, blue: 0.96),
                Color(red: 0.99, green: 0.95, blue: 0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.white.opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(red: 0.95, green: 0.88, blue: 0.8), lineWidth: 1)
            }
            .shadow(color: Color(red: 0.38, green: 0.2, blue: 0.08).opacity(0.05), radius: 10, y: 4)
    }

    private var darkDiagnosticsBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(red: 0.08, green: 0.06, blue: 0.05).opacity(0.94))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }

    private var spriteName: String {
        let family = isWarmRoll ? "flame" : "ice"

        switch viewModel.roll?.status {
        case .revealed, .readyToReveal:
            return "completed_\(family)"
        case .waitingForParticipants:
            return "waiting_\(family)"
        default:
            return "started_\(family)"
        }
    }

    private var isWarmRoll: Bool {
        viewModel.roll?.film_stock_id != FilmStock.fujifilmSuperia400.rawValue
    }

    private var accentColor: Color {
        isWarmRoll
            ? Color(red: 0.95, green: 0.32, blue: 0.02)
            : Color(red: 0.12, green: 0.56, blue: 1.0)
    }

    private var detailInk: Color {
        Color(red: 0.12, green: 0.1, blue: 0.09)
    }

    private var detailMuted: Color {
        Color(red: 0.44, green: 0.4, blue: 0.36)
    }

    private var feelDescription: String {
        isWarmRoll
            ? "A warm roll for everyday moments and memories."
            : "A cool roll for crisp moments and quiet memories."
    }

    private var createdDateLabel: String {
        guard let createdAt = viewModel.roll?.created_at else {
            return "Loading"
        }

        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var participantsLabel: String {
        if viewModel.isSharedRoll {
            let count = max(viewModel.participants.count, 1)
            return "\(count) joined"
        }

        return "Only you"
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
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(detailMuted)

            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(title == "Captured" ? detailInk : accentColor)

            Text("exposures")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(detailMuted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func capsuleLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.12))
            )
    }
}
