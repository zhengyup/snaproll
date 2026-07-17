import AVFoundation
import SwiftUI

struct V2CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: V2CaptureViewModel
    #if os(iOS)
    @StateObject private var orientationTracker = CaptureOrientationTracker()
    #endif
    private let onCaptureCompleted: () async -> Void

    init(
        roll: LocalRoll,
        currentParticipantID: UUID? = nil,
        currentParticipantDisplayName: String? = nil,
        dependencies: V2DependencyContainer,
        onCaptureCompleted: @escaping () async -> Void = {}
    ) {
        let providers = V2CaptureView.makeProviders()
        _viewModel = StateObject(
            wrappedValue: V2CaptureViewModel(
                roll: roll,
                currentParticipantID: currentParticipantID,
                currentParticipantDisplayName: currentParticipantDisplayName,
                exposureMirrorStore: dependencies.exposureMirrorStore,
                capturePipeline: V2LocalCapturePipeline(
                    exposureMirrorStore: dependencies.exposureMirrorStore,
                    photoStorageService: dependencies.photoStorageService
                ),
                photoStorageService: dependencies.photoStorageService,
                providers: providers
            )
        )
        self.onCaptureCompleted = onCaptureCompleted
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                cameraBackground

                if isLandscape {
                    landscapeCameraLayout(size: proxy.size)
                } else {
                    portraitCameraLayout(size: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        #if os(iOS)
        .snaprollPreferredOrientations([.portrait, .landscapeLeft, .landscapeRight])
        #endif
        .onAppear {
            #if os(iOS)
            orientationTracker.start()
            viewModel.updateCaptureOrientation(orientationTracker.orientation.videoOrientation)
            #endif
            viewModel.handleAppear()
        }
        #if os(iOS)
        .onChange(of: orientationTracker.orientation) { _, newOrientation in
            viewModel.updateCaptureOrientation(newOrientation.videoOrientation)
        }
        #endif
        .onDisappear {
            #if os(iOS)
            orientationTracker.stop()
            SnaprollOrientationController.setPreferredOrientations(.portrait)
            #endif
            viewModel.handleDisappear()
            Task {
                await onCaptureCompleted()
            }
        }
    }

    private var cameraBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.015, green: 0.014, blue: 0.012),
                Color(red: 0.045, green: 0.038, blue: 0.03),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func landscapeCameraLayout(size: CGSize) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                closeButton
                flashAutoIndicator(isLandscape: true)
                Spacer()
                exposureBadge
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            HStack(spacing: 18) {
                VStack(spacing: 10) {

                    viewfinder(isLandscape: true)
                        .frame(width: min(size.width * 0.82, 1240), height: min(size.height * 0.86, 710))

                    bottomStatusBar(isLandscape: true)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 30) {
                    shutterButton(size: 74)

                    flashButton
                }
                .frame(width: max(88, size.width * 0.1))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private func portraitCameraLayout(size: CGSize) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                closeButton
                flashAutoIndicator(isLandscape: false)

                Spacer()

                exposureBadge
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            Spacer(minLength: 6)

            viewfinder(isLandscape: false)
                .frame(width: min(size.width * 0.94, 470), height: min(size.height * 0.7, 760))

            Text("snaproll")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))

            Spacer(minLength: 12)

            HStack {
                exposureCounter
                    .frame(maxWidth: .infinity, alignment: .leading)

                shutterButton(size: 84)
                    .frame(maxWidth: .infinity)

                flashButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 24)

            if AppConfig.V2.isExposureDiagnosticsEnabled {
                diagnosticsStrip
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
    }

    private func flashAutoIndicator(isLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: isLandscape ? 15 : 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Auto")
                .font(.system(size: isLandscape ? 9 : 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(height: 44, alignment: .center)
    }

    @ViewBuilder
    private func viewfinder(isLandscape: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: isLandscape ? 28 : 30, style: .continuous)
                .fill(Color(red: 0.03, green: 0.03, blue: 0.028))
                .shadow(color: .black.opacity(0.75), radius: 22, y: 14)

            RoundedRectangle(cornerRadius: isLandscape ? 20 : 22, style: .continuous)
                .fill(Color.black)
                .padding(isLandscape ? 10 : 12)

            livePreview(isLandscape: isLandscape)
                .clipShape(RoundedRectangle(cornerRadius: isLandscape ? 16 : 20, style: .continuous))
                .padding(isLandscape ? 12 : 14)

            RoundedRectangle(cornerRadius: isLandscape ? 28 : 30, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)

            RoundedRectangle(cornerRadius: isLandscape ? 16 : 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                .padding(isLandscape ? 12 : 14)
        }
        .aspectRatio(isLandscape ? 2.18 : 0.58, contentMode: .fit)
    }

    @ViewBuilder
    private func livePreview(isLandscape: Bool) -> some View {
        if let cameraProvider = viewModel.cameraProvider,
           viewModel.selectedSourceKind == .deviceCamera {
            if cameraProvider.authorizationState == .authorized, cameraProvider.isPreviewReady {
                CameraPreviewView(
                    session: cameraProvider.previewSession,
                    lockedOrientation: previewVideoOrientation(isLandscapeFallback: isLandscape)
                )
            } else {
                cameraPreparingView(message: cameraProvider.statusMessage)
            }
        } else {
            developmentSamplePreview(isLandscape: isLandscape)
        }
    }

    private func previewVideoOrientation(isLandscapeFallback: Bool) -> AVCaptureVideoOrientation {
        #if os(iOS)
        return orientationTracker.orientation.videoOrientation
        #else
        return isLandscapeFallback ? .landscapeRight : .portrait
        #endif
    }

    private func cameraPreparingView(message: String?) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)

            Text(message ?? "Preparing camera")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func developmentSamplePreview(isLandscape: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.76, blue: 0.42),
                    Color(red: 0.29, green: 0.43, blue: 0.38),
                    Color(red: 0.08, green: 0.08, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("Sample Frame")
                    .font(.system(size: isLandscape ? 18 : 16, weight: .semibold, design: .rounded))
                Text("Local-only capture")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .opacity(0.72)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
    }

    private func bottomStatusBar(isLandscape: Bool) -> some View {
        HStack(alignment: .bottom) {
            exposureCounter

            Spacer()

            VStack(spacing: 4) {
                Text("snaproll")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))

                if let message = viewModel.lastCaptureMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            Spacer()

            if AppConfig.V2.isExposureDiagnosticsEnabled {
                sourcePicker
                    .frame(width: 190)
            } else {
                Color.clear.frame(width: 92, height: 40)
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                )
        }
        .buttonStyle(.plain)
    }

    private var exposureBadge: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(viewModel.remainingExposures)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("EXP")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(captureOrange)
        }
    }

    private var captureOrange: Color {
        Color(red: 0.95, green: 0.32, blue: 0.02)
    }

    private var exposureCounter: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: "camera.metering.center.weighted")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))

            Text("\(viewModel.remainingExposures)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private func shutterButton(size: CGFloat) -> some View {
        Button {
            Task {
                await viewModel.capture()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(viewModel.canCapture ? 0.95 : 0.35), lineWidth: 4)
                Circle()
                    .fill(.white.opacity(viewModel.canCapture ? 0.98 : 0.3))
                    .padding(9)

                if viewModel.isCapturing {
                    ProgressView()
                        .tint(.black)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canCapture)
    }

    private var flashButton: some View {
        Button {
            viewModel.retryPermissionFlow()
        } label: {
            Image(systemName: "bolt.slash")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        }
                )
        }
        .buttonStyle(.plain)
    }

    private var sourcePicker: some View {
        Picker("Image Source", selection: $viewModel.selectedSourceKind) {
            ForEach(viewModel.availableSourceKinds) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    private var diagnosticsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.availableSourceKinds.count > 1 {
                sourcePicker
            }

            if let message = viewModel.stateMessage {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red.opacity(0.9))
            }

            Text("\(viewModel.capturedExposures) captured / \(viewModel.totalExposures) total")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))

            if let message = viewModel.lastCaptureMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.07))
        )
    }

    @ViewBuilder
    private var developmentDiagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Exposure Diagnostics")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(viewModel.mirroredExposures, id: \.id) { exposure in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Exposure \(exposure.exposure_number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private static func makeProviders() -> [V2ImageSourceKind: any ImageSourceProvider] {
        var providers: [V2ImageSourceKind: any ImageSourceProvider] = [
            .developmentSample: DevelopmentSampleImageSourceProvider()
        ]

        #if os(iOS)
        providers[.deviceCamera] = DeviceCameraImageSourceProvider()
        #endif

        return providers
    }
}
