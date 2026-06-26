import SwiftUI
import MediaPlayer

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel: CameraViewModel

    init(
        roll: Roll,
        cameraService: CameraService? = nil,
        photoStorageService: PhotoStorageService? = nil,
        localStorageService: LocalStorageService? = nil,
        onRollUpdated: ((Roll) -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: CameraViewModel(
                roll: roll,
                cameraService: cameraService,
                photoStorageService: photoStorageService,
                localStorageService: localStorageService,
                onRollUpdated: onRollUpdated
            )
        )
    }

    var body: some View {
        ZStack {
            cameraBackdrop.ignoresSafeArea()

            if viewModel.authorizationState == .authorized, viewModel.isPreviewReady {
                captureInterface
            } else {
                permissionStateView
            }
        }
        .background {
            HardwareVolumeCaptureView(onReady: viewModel.attachHardwareShutterVolumeView)
                .frame(width: 2, height: 2)
                .allowsHitTesting(false)
        }
        .onAppear {
            viewModel.handleAppear()
        }
        .onDisappear {
            viewModel.handleDisappear()
        }
        .onChange(of: viewModel.shouldDismiss) {
            guard viewModel.shouldDismiss else {
                return
            }

            dismiss()
        }
        .snaprollScreenNavigation()
        .snaprollPreferredOrientations(.landscapeRight)
    }

    private var cameraBackdrop: some View {
        ZStack {
            Color(red: 0.03, green: 0.03, blue: 0.03)

            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.09, blue: 0.08).opacity(0.65),
                    Color.clear,
                    Color.black.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.16, green: 0.15, blue: 0.12).opacity(0.24),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 560
            )
        }
    }

    private var captureInterface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)

            VStack(spacing: 0) {
                headerBar

                Spacer(minLength: 22)

                HStack(alignment: .center, spacing: 34) {
                    viewfinderPanel
                    captureRail
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 20)

                bottomBar
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .padding(14)
    }

    private var headerBar: some View {
        ZStack {
            HStack {
                circleControl(symbol: "chevron.left") {
                    dismiss()
                }

                Spacer()
            }

            VStack(spacing: 6) {
                Text(viewModel.roll.name)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(AppTheme.creamText)
                    .lineLimit(1)

                Text(headerSubtitle)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AppTheme.softText)
            }
            .frame(maxWidth: 420)
        }
    }

    private var viewfinderPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)

            CameraPreviewView(
                session: viewModel.previewSession,
                lockedOrientation: .landscapeRight
            )
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(10)
        }
        .frame(maxWidth: 880)
        .shadow(color: Color.black.opacity(0.32), radius: 28, y: 16)
    }

    private var captureRail: some View {
        VStack(spacing: 26) {
            Spacer()

            shutterButton

            Spacer(minLength: 32)

            flashButton

            Spacer()
        }
        .frame(width: 118)
    }

    private var permissionStateView: some View {
        VStack(spacing: 18) {
            if viewModel.authorizationState == .authorized {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.primaryAction)
                    .scaleEffect(1.2)
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: permissionIcon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(AppTheme.primaryAction)
            }

            VStack(spacing: 10) {
                Text(permissionTitle)
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(AppTheme.creamText)

                Text(permissionMessage)
                    .font(.title3)
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsPermissionActions {
                VStack(spacing: 12) {
                    Button {
                        viewModel.retryPermissionFlow()
                    } label: {
                        Text(primaryPermissionActionTitle)
                            .font(.headline)
                            .foregroundStyle(Color.black.opacity(0.88))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.primaryAction)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if let settingsURL, showsSettingsAction {
                        Button {
                            openURL(settingsURL)
                        } label: {
                            Text("Open Settings")
                                .font(.headline)
                                .foregroundStyle(AppTheme.creamText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.softText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 420)
    }

    private var bottomBar: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.roll.film.displayName)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(AppTheme.color(from: viewModel.roll.film.accentHex))

                if let message = cameraStatusText {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.softText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(viewModel.roll.capturedMemories) / \(viewModel.roll.shotLimit)")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.creamText)

                Text(viewModel.roll.exposuresRemaining == 1 ? "1 exposure left" : "\(viewModel.roll.exposuresRemaining) exposures left")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.softText)
            }
        }
    }

    private var shutterButton: some View {
        Button {
            viewModel.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 106, height: 106)

                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 4)
                    .frame(width: 106, height: 106)

                Circle()
                    .fill(Color.white)
                    .frame(width: 82, height: 82)

                if viewModel.isCapturing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.black.opacity(0.72))
                        .scaleEffect(0.9)
                }
            }
            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!canCapture)
        .opacity(canCapture ? 1 : 0.56)
    }

    private var flashButton: some View {
        Button {
            viewModel.toggleFlashMode()
        } label: {
            Image(systemName: viewModel.flashMode == .on ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(viewModel.flashMode == .on ? AppTheme.primaryAction : AppTheme.creamText)
                .frame(width: 54, height: 54)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(viewModel.flashMode == .on ? AppTheme.primaryAction.opacity(0.55) : Color.white.opacity(0.05), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isFlashAvailable)
        .opacity(viewModel.isFlashAvailable ? 1 : 0.35)
    }

    private func circleControl(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.creamText)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var permissionIcon: String {
        switch viewModel.authorizationState {
        case .authorized:
            return "camera"
        case .notDetermined:
            return "camera.aperture"
        case .denied, .restricted:
            return "camera.fill.badge.ellipsis"
        case .unavailable:
            return "camera.metering.unknown"
        }
    }

    private var permissionTitle: String {
        switch viewModel.authorizationState {
        case .authorized:
            return "Preparing Camera"
        case .notDetermined:
            return "Camera Access"
        case .denied:
            return "Camera Access Needed"
        case .restricted:
            return "Camera Restricted"
        case .unavailable:
            return "Camera Unavailable"
        }
    }

    private var permissionMessage: String {
        switch viewModel.authorizationState {
        case .authorized:
            return "Setting up a calm, focused viewfinder for your roll."
        case .notDetermined:
            return "Snaproll needs camera access so you can capture memories directly into your roll."
        case .denied:
            return "Snaproll needs camera access to let you shoot intentionally inside the app."
        case .restricted:
            return "Camera access is currently restricted on this device."
        case .unavailable:
            return "This device does not currently have an available camera."
        }
    }

    private var primaryPermissionActionTitle: String {
        switch viewModel.authorizationState {
        case .notDetermined:
            return "Allow Camera Access"
        case .denied, .restricted:
            return "Retry"
        case .authorized, .unavailable:
            return "Retry"
        }
    }

    private var canCapture: Bool {
        viewModel.authorizationState == .authorized && viewModel.isPreviewReady && !viewModel.isCapturing && !viewModel.roll.isFinished
    }

    private var headerSubtitle: String {
        if let message = cameraStatusText {
            return message
        }

        return viewModel.roll.exposuresRemaining == 1
            ? "1 exposure left"
            : "\(viewModel.roll.exposuresRemaining) exposures left"
    }

    private var cameraStatusText: String? {
        if let captureFeedbackMessage = viewModel.captureFeedbackMessage {
            return captureFeedbackMessage
        }

        return liveStatusMessage
    }

    private var liveStatusMessage: String? {
        guard viewModel.authorizationState == .authorized, viewModel.isPreviewReady else {
            return nil
        }

        return viewModel.statusMessage
    }

    private var showsPermissionActions: Bool {
        switch viewModel.authorizationState {
        case .authorized:
            return false
        case .notDetermined, .denied, .restricted, .unavailable:
            return true
        }
    }

    private var showsSettingsAction: Bool {
        switch viewModel.authorizationState {
        case .denied, .restricted:
            return true
        case .authorized, .notDetermined, .unavailable:
            return false
        }
    }

    private var settingsURL: URL? {
        #if os(iOS)
        return URL(string: UIApplication.openSettingsURLString)
        #else
        return nil
        #endif
    }
}

#if os(iOS)
private struct HardwareVolumeCaptureView: UIViewRepresentable {
    let onReady: (MPVolumeView) -> Void

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeView.alpha = 0.01
        container.addSubview(volumeView)

        DispatchQueue.main.async {
            onReady(volumeView)
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let volumeView = uiView.subviews.first(where: { $0 is MPVolumeView }) as? MPVolumeView else {
            return
        }

        DispatchQueue.main.async {
            onReady(volumeView)
        }
    }
}
#endif

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView(roll: .placeholder)
    }
}
