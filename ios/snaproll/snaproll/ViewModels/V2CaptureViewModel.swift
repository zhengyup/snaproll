import AVFoundation
import Combine
import Foundation
#if os(iOS)
import UIKit
#endif

@MainActor
final class V2CaptureViewModel: ObservableObject {
    @Published private(set) var roll: LocalRoll
    @Published private(set) var mirroredExposures: [LocalExposure] = []
    @Published private(set) var stateMessage: String?
    @Published private(set) var isCapturing = false
    @Published private(set) var lastCaptureMessage: String?
    @Published var selectedSourceKind: V2ImageSourceKind

    let rollID: UUID

    private let exposureMirrorStore: any ExposureMirrorStore
    private let capturePipeline: V2LocalCapturePipeline
    private let photoStorageService: PhotoStorageService
    private let providers: [V2ImageSourceKind: any ImageSourceProvider]

    init(
        roll: LocalRoll,
        exposureMirrorStore: any ExposureMirrorStore,
        capturePipeline: V2LocalCapturePipeline,
        photoStorageService: PhotoStorageService,
        providers: [V2ImageSourceKind: any ImageSourceProvider]
    ) {
        self.roll = roll
        self.rollID = roll.id
        self.exposureMirrorStore = exposureMirrorStore
        self.capturePipeline = capturePipeline
        self.photoStorageService = photoStorageService
        self.providers = providers

        if let cameraProvider = providers[.deviceCamera] as? DeviceCameraImageSourceProvider,
           cameraProvider.authorizationState != .unavailable {
            self.selectedSourceKind = .deviceCamera
        } else {
            self.selectedSourceKind = .developmentSample
        }
    }

    var totalExposures: Int {
        mirroredExposures.count
    }

    var capturedExposures: Int {
        mirroredExposures.filter {
            $0.sync_state == .localOnly
                || $0.sync_state == .synced
                || $0.local_original_path != nil
                || $0.cloud_storage_path != nil
        }.count
    }

    var remainingExposures: Int {
        max(totalExposures - capturedExposures, 0)
    }

    var canCapture: Bool {
        !isCapturing && remainingExposures > 0
    }

    var availableSourceKinds: [V2ImageSourceKind] {
        providers.keys.sorted { $0.rawValue < $1.rawValue }
    }

    var cameraProvider: DeviceCameraImageSourceProvider? {
        providers[.deviceCamera] as? DeviceCameraImageSourceProvider
    }

    var currentProvider: (any ImageSourceProvider)? {
        providers[selectedSourceKind]
    }

    var shouldShowDevelopmentPreview: Bool {
        AppConfig.V2.isExposureDiagnosticsEnabled && selectedSourceKind == .developmentSample
    }

    func handleAppear() {
        cameraProvider?.handleAppear()

        Task {
            await loadMirroredExposures()
        }
    }

    func handleDisappear() {
        cameraProvider?.handleDisappear()
    }

    func retryPermissionFlow() {
        cameraProvider?.retryPermissionFlow()
    }

    func capture() async {
        guard canCapture, let provider = currentProvider else {
            return
        }

        isCapturing = true
        stateMessage = nil
        defer { isCapturing = false }

        do {
            let result = try await capturePipeline.captureNextExposure(forRollID: rollID, using: provider)
            await loadMirroredExposures()

            if remainingExposures == 0 {
                lastCaptureMessage = "Final local exposure captured"
            } else {
                lastCaptureMessage = "Exposure \(result.exposureNumber) captured"
            }
        } catch {
            stateMessage = error.localizedDescription
        }
    }

    func localFileExists(for exposure: LocalExposure) -> Bool {
        guard let localPath = exposure.local_original_path else {
            return false
        }

        return photoStorageService.fileExists(at: localPath)
    }

    func loadThumbnail(for exposure: LocalExposure) -> UIImage? {
        guard let localPath = exposure.local_original_path else {
            return nil
        }

        return photoStorageService.loadImage(at: localPath)
    }

    private func loadMirroredExposures() async {
        do {
            mirroredExposures = try await exposureMirrorStore.fetchExposures(forRollID: rollID)
                .sorted(by: { $0.exposure_number < $1.exposure_number })
        } catch {
            stateMessage = error.localizedDescription
        }
    }
}
