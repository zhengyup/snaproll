import AVFoundation
import Combine
import Foundation
#if os(iOS)
import UIKit
#endif

struct CapturedImagePayload: Sendable {
    let data: Data
    let fileExtension: String
}

enum V2ImageSourceKind: String, CaseIterable, Identifiable, Sendable {
    case deviceCamera
    case developmentSample

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deviceCamera:
            return "Camera"
        case .developmentSample:
            return "Sample"
        }
    }
}

protocol ImageSourceProvider: AnyObject {
    var kind: V2ImageSourceKind { get }
    func captureImage() async throws -> CapturedImagePayload
}

@MainActor
protocol CameraPreviewImageSourceProvider: ImageSourceProvider {
    var previewSession: AVCaptureSession { get }
    var authorizationState: CameraAuthorizationState { get }
    var isPreviewReady: Bool { get }
    var statusMessage: String? { get }

    func handleAppear()
    func handleDisappear()
    func retryPermissionFlow()
}

@MainActor
final class DeviceCameraImageSourceProvider: ObservableObject, CameraPreviewImageSourceProvider {
    @Published private(set) var authorizationState: CameraAuthorizationState
    @Published private(set) var isPreviewReady = false
    @Published private(set) var statusMessage: String?

    let kind: V2ImageSourceKind = .deviceCamera
    let previewSession: AVCaptureSession

    private let cameraService: CameraService
    private var captureVideoOrientation: AVCaptureVideoOrientation = .portrait

    init(cameraService: CameraService? = nil) {
        let service = cameraService ?? CameraService()
        self.cameraService = service
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

    func updateCaptureOrientation(_ orientation: AVCaptureVideoOrientation) {
        captureVideoOrientation = orientation
    }

    func captureImage() async throws -> CapturedImagePayload {
        let data = try await cameraService.capturePhoto(
            flashMode: .off,
            videoOrientation: captureVideoOrientation
        )
        return CapturedImagePayload(data: data, fileExtension: "jpg")
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
}

final class DevelopmentSampleImageSourceProvider: ImageSourceProvider {
    let kind: V2ImageSourceKind = .developmentSample

    func captureImage() async throws -> CapturedImagePayload {
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1800))
        let timestamp = Date.now.formatted(date: .abbreviated, time: .standard)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: 1200, height: 1800))
            UIColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1).setFill()
            context.fill(rect)

            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.96, green: 0.78, blue: 0.21, alpha: 1).cgColor,
                    UIColor(red: 0.52, green: 0.33, blue: 0.14, alpha: 1).cgColor,
                    UIColor(red: 0.16, green: 0.15, blue: 0.19, alpha: 1).cgColor
                ] as CFArray,
                locations: [0.0, 0.45, 1.0]
            )

            context.cgContext.drawLinearGradient(
                gradient!,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 1200, y: 1800),
                options: []
            )

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 74, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.82)
            ]

            NSString(string: "Snaproll Dev").draw(at: CGPoint(x: 84, y: 112), withAttributes: titleAttributes)
            NSString(string: timestamp).draw(at: CGPoint(x: 88, y: 210), withAttributes: subtitleAttributes)

            UIColor.white.withAlphaComponent(0.12).setStroke()
            let frame = UIBezierPath(roundedRect: CGRect(x: 84, y: 320, width: 1032, height: 1260), cornerRadius: 44)
            frame.lineWidth = 6
            frame.stroke()

            UIColor.white.withAlphaComponent(0.18).setFill()
            for index in 0..<5 {
                let size = CGFloat(84 + index * 14)
                let origin = CGPoint(x: 180 + CGFloat(index) * 146, y: 620 + CGFloat(index.isMultiple(of: 2) ? 0 : 110))
                context.cgContext.fillEllipse(in: CGRect(origin: origin, size: CGSize(width: size, height: size)))
            }
        }

        guard let data = image.pngData() else {
            throw CameraServiceError.processingFailed
        }

        return CapturedImagePayload(data: data, fileExtension: "png")
        #else
        throw CameraServiceError.processingFailed
        #endif
    }
}
