import AVFoundation
import Combine
import Foundation

#if os(iOS)
import UIKit
#endif

enum CaptureDeviceOrientation: Equatable, Sendable {
    case portrait
    case landscapeLeft
    case landscapeRight

    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        }
    }

    var isLandscape: Bool {
        switch self {
        case .portrait:
            return false
        case .landscapeLeft, .landscapeRight:
            return true
        }
    }

    #if os(iOS)
    static func validOrientation(from deviceOrientation: UIDeviceOrientation) -> CaptureDeviceOrientation? {
        switch deviceOrientation {
        case .portrait:
            return .portrait
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown, .faceUp, .faceDown, .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
    #endif
}

#if os(iOS)
@MainActor
final class CaptureOrientationTracker: ObservableObject {
    @Published private(set) var orientation: CaptureDeviceOrientation

    private var observer: NSObjectProtocol?

    init(initialOrientation: CaptureDeviceOrientation = .portrait) {
        self.orientation = initialOrientation
    }

    func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        update(from: UIDevice.current.orientation)

        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let deviceOrientation = UIDevice.current.orientation
            guard let tracker = self else {
                return
            }

            Task { @MainActor in
                tracker.update(from: deviceOrientation)
            }
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func update(from deviceOrientation: UIDeviceOrientation) {
        guard let validOrientation = CaptureDeviceOrientation.validOrientation(from: deviceOrientation) else {
            return
        }

        orientation = validOrientation
    }
}
#endif
