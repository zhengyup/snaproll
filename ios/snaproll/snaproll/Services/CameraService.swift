@preconcurrency import AVFoundation
import Foundation
#if os(iOS)
import UIKit
#endif

enum CameraAuthorizationState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unavailable
}

final class CameraService {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.pzy.snaproll.camera-session")
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var isRunning = false
    private var captureDelegates: [UUID: PhotoCaptureDelegate] = [:]

    var authorizationState: CameraAuthorizationState {
        guard AVCaptureDevice.default(for: .video) != nil else {
            return .unavailable
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    func requestAccess() async -> CameraAuthorizationState {
        guard authorizationState != .unavailable else {
            return .unavailable
        }

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : authorizationState
    }

    func prepareSessionIfNeeded() async throws {
        guard authorizationState == .authorized else {
            return
        }

        if isConfigured {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureSession()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startSession() {
        guard authorizationState == .authorized else {
            return
        }

        sessionQueue.async {
            guard self.isConfigured, !self.isRunning else {
                return
            }

            self.session.startRunning()
            self.isRunning = self.session.isRunning
        }
    }

    func stopSession() {
        sessionQueue.async {
            guard self.isRunning else {
                return
            }

            self.session.stopRunning()
            self.isRunning = false
        }
    }

    func capturePhoto() async throws -> Data {
        guard authorizationState == .authorized else {
            throw CameraServiceError.notAuthorized
        }

        try await prepareSessionIfNeeded()

        return try await withCheckedThrowingContinuation { continuation in
            guard self.isConfigured else {
                continuation.resume(throwing: CameraServiceError.captureUnavailable)
                return
            }

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off

            let captureID = UUID()
            let delegate = PhotoCaptureDelegate(id: captureID) { [weak self] result in
                guard let self else {
                    continuation.resume(throwing: CameraServiceError.captureFailed)
                    return
                }

                DispatchQueue.main.async {
                    self.captureDelegates.removeValue(forKey: captureID)
                }

                switch result {
                case .success(let photoData):
                    continuation.resume(returning: photoData)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            DispatchQueue.main.async {
                self.captureDelegates[captureID] = delegate

                if let connection = self.photoOutput.connection(with: .video),
                   connection.isVideoOrientationSupported {
                    connection.videoOrientation = CameraService.currentVideoOrientation
                }

                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private func configureSession() throws {
        guard !isConfigured else {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        defer {
            session.commitConfiguration()
        }

        let existingInputs = session.inputs
        for input in existingInputs {
            session.removeInput(input)
        }

        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw CameraServiceError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraServiceError.cannotAddInput
        }

        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            throw CameraServiceError.cannotAddOutput
        }

        session.addOutput(photoOutput)
        isConfigured = true
    }
}

#if os(iOS)
private extension CameraService {
    static var currentVideoOrientation: AVCaptureVideoOrientation {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .portrait
        }

        switch windowScene.effectiveGeometry.interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
        }
    }
}
#endif

enum CameraServiceError: LocalizedError {
    case cameraUnavailable
    case notAuthorized
    case cannotAddInput
    case cannotAddOutput
    case captureUnavailable
    case captureFailed
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "A camera is not available on this device."
        case .notAuthorized:
            return "Camera access is required before capturing a photo."
        case .cannotAddInput:
            return "The camera session could not be configured."
        case .cannotAddOutput:
            return "The camera capture output could not be configured."
        case .captureUnavailable:
            return "The camera is not ready to capture yet."
        case .captureFailed:
            return "Snaproll couldn't capture that exposure."
        case .processingFailed:
            return "The captured image could not be processed."
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let id: UUID

    private let completion: (Result<Data, Error>) -> Void

    init(id: UUID, completion: @escaping (Result<Data, Error>) -> Void) {
        self.id = id
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraServiceError.processingFailed))
            return
        }

        completion(.success(data))
    }
}
