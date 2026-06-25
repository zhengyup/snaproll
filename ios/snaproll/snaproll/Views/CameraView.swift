import SwiftUI

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
            AppTheme.background.ignoresSafeArea()

            if viewModel.authorizationState == .authorized, viewModel.isPreviewReady {
                cameraPreview
            } else {
                permissionStateView
            }

            cameraChrome
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
        .snaprollPreferredOrientations(.landscape)
    }

    private var cameraPreview: some View {
        CameraPreviewView(session: viewModel.previewSession)
            .ignoresSafeArea()
            .overlay(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.45),
                        .clear,
                        Color.black.opacity(0.40)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
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

    private var cameraChrome: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.creamText)
                        .frame(width: 42, height: 42)
                        .background(Color.black.opacity(0.28))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                exposureCounter
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 18) {
                if let captureFeedbackMessage = viewModel.captureFeedbackMessage {
                    captureFeedback(message: captureFeedbackMessage)
                } else if let statusMessage = liveStatusMessage {
                    captureFeedback(message: statusMessage)
                }

                shutterButton

                Text(viewModel.roll.name)
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.86))
            }
            .padding(.bottom, 34)
        }
    }

    private var exposureCounter: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("EXPOSURES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(AppTheme.primaryAction)

            Text("\(viewModel.roll.capturedMemories) / \(viewModel.roll.shotLimit)")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.creamText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var shutterButton: some View {
        Button {
            viewModel.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(shutterStrokeColor, lineWidth: 4)
                    .frame(width: 86, height: 86)

                Circle()
                    .fill(shutterFillColor)
                    .frame(width: 66, height: 66)

                if viewModel.isCapturing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.creamText)
                        .scaleEffect(0.85)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canCapture)
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

    private var shutterStrokeColor: Color {
        canCapture ? Color.white.opacity(0.95) : Color.white.opacity(0.45)
    }

    private var shutterFillColor: Color {
        canCapture ? Color.white.opacity(0.16) : Color.white.opacity(0.08)
    }

    private var liveStatusMessage: String? {
        guard viewModel.authorizationState == .authorized, viewModel.isPreviewReady else {
            return nil
        }

        return viewModel.statusMessage
    }

    private func captureFeedback(message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppTheme.creamText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.32))
            .clipShape(Capsule())
            .transition(.opacity)
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

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView(roll: .placeholder)
    }
}
