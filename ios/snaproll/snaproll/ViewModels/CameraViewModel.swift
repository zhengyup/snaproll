import AVFoundation
import Combine
import Foundation

@MainActor
final class CameraViewModel: ObservableObject {
    @Published private(set) var authorizationState: CameraAuthorizationState
    @Published private(set) var statusMessage: String?
    @Published private(set) var isPreviewReady = false
    @Published private(set) var roll: Roll
    @Published private(set) var isCapturing = false
    @Published private(set) var captureFeedbackMessage: String?
    @Published private(set) var shouldDismiss = false

    let previewSession: AVCaptureSession

    private let cameraService: CameraService
    private let photoStorageService: PhotoStorageService
    private let localStorageService: LocalStorageService
    private let onRollUpdated: ((Roll) -> Void)?

    init(
        roll: Roll,
        cameraService: CameraService? = nil,
        photoStorageService: PhotoStorageService? = nil,
        localStorageService: LocalStorageService? = nil,
        onRollUpdated: ((Roll) -> Void)? = nil
    ) {
        self.roll = roll
        let service = cameraService ?? CameraService()
        self.cameraService = service
        self.photoStorageService = photoStorageService ?? PhotoStorageService()
        self.localStorageService = localStorageService ?? LocalStorageService()
        self.onRollUpdated = onRollUpdated
        self.previewSession = service.session
        self.authorizationState = service.authorizationState
    }

    func handleAppear() {
        Task {
            await prepareCamera()
        }
    }

    func handleDisappear() {
        cameraService.stopSession()
    }

    func retryPermissionFlow() {
        Task {
            await prepareCamera(forceRequest: true)
        }
    }

    func capturePhoto() {
        guard !isCapturing, isPreviewReady, authorizationState == .authorized, !roll.isFinished else {
            return
        }

        isCapturing = true
        statusMessage = nil
        captureFeedbackMessage = nil

        Task {
            do {
                let capturedData = try await cameraService.capturePhoto()
                let updatedRoll = try persistCapture(from: capturedData)

                roll = updatedRoll
                onRollUpdated?(updatedRoll)

                let message = captureMessage(for: updatedRoll)
                captureFeedbackMessage = message

                if updatedRoll.isFinished {
                    try await Task.sleep(nanoseconds: AppConfig.Photos.completionDismissDelayNanoseconds)
                    shouldDismiss = true
                } else {
                    try await Task.sleep(nanoseconds: AppConfig.Photos.captureFeedbackDurationNanoseconds)
                    if captureFeedbackMessage == message {
                        captureFeedbackMessage = nil
                    }
                }
            } catch is CancellationError {
            } catch {
                statusMessage = error.localizedDescription
            }

            isCapturing = false
        }
    }

    private func prepareCamera(forceRequest: Bool = false) async {
        statusMessage = nil

        switch authorizationState {
        case .authorized:
            await configureAndStartSession()
        case .notDetermined:
            let result = await cameraService.requestAccess()
            authorizationState = result

            if result == .authorized {
                await configureAndStartSession()
            }
        case .denied, .restricted:
            if forceRequest {
                authorizationState = cameraService.authorizationState
            }
        case .unavailable:
            statusMessage = CameraServiceError.cameraUnavailable.errorDescription
        }
    }

    private func configureAndStartSession() async {
        do {
            try await cameraService.prepareSessionIfNeeded()
            isPreviewReady = true
            cameraService.startSession()
        } catch {
            isPreviewReady = false
            statusMessage = error.localizedDescription
        }
    }

    private func persistCapture(from imageData: Data) throws -> Roll {
        let photoID = UUID()
        let nextExposureNumber = roll.exposuresUsed + 1
        let savedURL = try photoStorageService.savePhotoData(imageData, for: roll.id, photoID: photoID)

        let photo = Photo(
            id: photoID,
            rollID: roll.id,
            localPath: savedURL.path,
            createdAt: .now,
            exposureNumber: nextExposureNumber
        )

        let previousPhotos = localStorageService.loadPhotos()
        let previousRolls = localStorageService.loadRolls()
        let updatedRoll = roll.registeringCapture()

        guard let rollIndex = previousRolls.firstIndex(where: { $0.id == roll.id }) else {
            try? photoStorageService.deletePhoto(at: savedURL.path)
            throw CameraCapturePersistenceError.rollNotFound
        }

        var updatedPhotos = previousPhotos
        updatedPhotos.append(photo)

        var updatedRolls = previousRolls
        updatedRolls[rollIndex] = updatedRoll

        do {
            try localStorageService.savePhotos(updatedPhotos)

            do {
                try localStorageService.saveRolls(updatedRolls)
            } catch {
                try? localStorageService.savePhotos(previousPhotos)
                try? photoStorageService.deletePhoto(at: savedURL.path)
                throw error
            }
        } catch {
            try? photoStorageService.deletePhoto(at: savedURL.path)
            throw error
        }

        return updatedRoll
    }

    private func captureMessage(for roll: Roll) -> String {
        if roll.isFinished {
            return "Final exposure captured"
        }

        if roll.exposuresRemaining == 1 {
            return "1 exposure remaining"
        }

        return "Exposure \(roll.exposuresUsed) captured"
    }
}

enum CameraCapturePersistenceError: LocalizedError {
    case rollNotFound

    var errorDescription: String? {
        switch self {
        case .rollNotFound:
            return "This roll could not be updated after capture."
        }
    }
}
