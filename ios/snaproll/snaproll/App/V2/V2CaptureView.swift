import AVFoundation
import SwiftUI

struct V2CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: V2CaptureViewModel
    private let onCaptureCompleted: () async -> Void

    init(
        roll: LocalRoll,
        dependencies: V2DependencyContainer,
        onCaptureCompleted: @escaping () async -> Void = {}
    ) {
        let providers = V2CaptureView.makeProviders()
        _viewModel = StateObject(
            wrappedValue: V2CaptureViewModel(
                roll: roll,
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sourcePicker
                previewCard
                progressCard
                captureButton

                if AppConfig.V2.isExposureDiagnosticsEnabled {
                    developmentDiagnostics
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
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.handleAppear()
        }
        .onDisappear {
            viewModel.handleDisappear()
            Task {
                await onCaptureCompleted()
            }
        }
    }

    private var sourcePicker: some View {
        Group {
            if AppConfig.V2.isExposureDiagnosticsEnabled && viewModel.availableSourceKinds.count > 1 {
                Picker("Image Source", selection: $viewModel.selectedSourceKind) {
                    ForEach(viewModel.availableSourceKinds) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let cameraProvider = viewModel.cameraProvider,
               viewModel.selectedSourceKind == .deviceCamera {
                if cameraProvider.authorizationState == .authorized, cameraProvider.isPreviewReady {
                    CameraPreviewView(
                        session: cameraProvider.previewSession,
                        lockedOrientation: .portrait
                    )
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Camera unavailable")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(cameraProvider.statusMessage ?? "Allow camera access to capture into the next exposure.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))

                        Button("Retry Camera Access") {
                            viewModel.retryPermissionFlow()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Development Sample Source")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("This source generates a local sample image so the V2 exposure-filling pipeline can be tested without camera hardware.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.95, green: 0.76, blue: 0.18),
                                    Color(red: 0.42, green: 0.28, blue: 0.12),
                                    Color(red: 0.16, green: 0.15, blue: 0.19)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 320)
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Local-only sample")
                                    .font(.title3.weight(.semibold))
                                Text("Sync starts after you return to the roll.")
                                    .font(.footnote)
                            }
                            .foregroundStyle(.white)
                            .padding(20)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exposure Progress")
                .font(.headline)
                .foregroundStyle(.white)

            HStack {
                metric(title: "Captured", value: "\(viewModel.capturedExposures)")
                metric(title: "Remaining", value: "\(viewModel.remainingExposures)")
                metric(title: "Total", value: "\(viewModel.totalExposures)")
            }

            if let message = viewModel.lastCaptureMessage {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            if let stateMessage = viewModel.stateMessage {
                Text(stateMessage)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var captureButton: some View {
        Button {
            Task {
                await viewModel.capture()
            }
        } label: {
            if viewModel.isCapturing {
                ProgressView()
                    .tint(.black)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Capture Next Exposure")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.94, green: 0.76, blue: 0.13))
        )
        .disabled(!viewModel.canCapture)
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

                    Text(exposure.sync_state.rawValue)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(viewModel.localFileExists(for: exposure) ? "Local file exists" : "No local file")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))

                    if let localPath = exposure.local_original_path {
                        Text(localPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.58))
                            .textSelection(.enabled)
                    }

                    if let capturedAt = exposure.captured_at {
                        Text(capturedAt.formatted(date: .abbreviated, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    if let thumbnail = viewModel.loadThumbnail(for: exposure) {
                        Image(uiImage: thumbnail)
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func metric(title: String, value: String) -> some View {
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
