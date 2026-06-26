import AVFAudio
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class HardwareShutterService {
    private weak var attachedVolumeView: MPVolumeView?
    private var volumeNotificationObserver: NSObjectProtocol?
    private var volumeObservation: NSKeyValueObservation?
    private var onShutterPressed: (() -> Void)?
    private var baselineVolume: Float = 0.5
    private var lastKnownVolume: Float = 0.5
    private var isResettingVolume = false

    func startListening(onShutterPressed: @escaping () -> Void) {
        stopListening()

        self.onShutterPressed = onShutterPressed

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.ambient, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
        }

        baselineVolume = normalizedBaseline(for: audioSession.outputVolume)
        lastKnownVolume = audioSession.outputVolume

        volumeObservation = audioSession.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            let newVolume = change.newValue
            DispatchQueue.main.async {
                guard let self, let newVolume else {
                    return
                }

                self.handleHardwareShutterChange(updatedVolume: newVolume)
            }
        }

        volumeNotificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String
            let rawVolume = notification.userInfo?["AVSystemController_AudioVolumeNotificationParameter"]
            let updatedVolume = (rawVolume as? NSNumber)?.floatValue

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                guard reason == "ExplicitVolumeChange" else {
                    return
                }

                self.handleHardwareShutterChange(updatedVolume: updatedVolume ?? self.lastKnownVolume)
            }
        }
    }

    func stopListening() {
        if let volumeNotificationObserver {
            NotificationCenter.default.removeObserver(volumeNotificationObserver)
            self.volumeNotificationObserver = nil
        }

        volumeObservation = nil
        onShutterPressed = nil
        isResettingVolume = false
    }

    func attachVolumeView(_ volumeView: MPVolumeView) {
        attachedVolumeView = volumeView
        resetSystemVolumeIfPossible(using: volumeView)
    }

    private func handleHardwareShutterChange(updatedVolume: Float) {
        guard !isResettingVolume else {
            return
        }

        guard abs(updatedVolume - lastKnownVolume) > 0.0001 else {
            return
        }

        lastKnownVolume = updatedVolume
        onShutterPressed?()
        resetSystemVolumeIfPossible()
    }

    private func normalizedBaseline(for currentVolume: Float) -> Float {
        min(max(currentVolume, 0.2), 0.8)
    }

    private func resetSystemVolumeIfPossible(using providedVolumeView: MPVolumeView? = nil) {
        guard let volumeSlider = (providedVolumeView ?? attachedVolumeView ?? findVolumeView())?.subviews.compactMap({ $0 as? UISlider }).first else {
            return
        }

        isResettingVolume = true
        volumeSlider.setValue(baselineVolume, animated: false)
        volumeSlider.sendActions(for: .touchUpInside)
        volumeSlider.sendActions(for: .valueChanged)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else {
                return
            }

            self.lastKnownVolume = self.baselineVolume
            self.isResettingVolume = false
        }
    }

    private func findVolumeView() -> MPVolumeView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .flatMap(recursiveSubviews(in:))
            .first(where: { $0 is MPVolumeView }) as? MPVolumeView
    }

    private func recursiveSubviews(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(recursiveSubviews(in:))
    }
}
