import AVFoundation
import SwiftUI

#if os(iOS)
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let lockedOrientation: AVCaptureVideoOrientation

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.lockedOrientation = lockedOrientation
        view.updatePreviewOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.lockedOrientation = lockedOrientation
        uiView.updatePreviewOrientation()
    }
}

final class PreviewView: UIView {
    var lockedOrientation: AVCaptureVideoOrientation = .landscapeRight

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer backing layer.")
        }
        return layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewOrientation()
    }

    func updatePreviewOrientation() {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported else {
            return
        }

        connection.videoOrientation = lockedOrientation
    }
}
#elseif os(macOS)
import AppKit

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewHostingView {
        let view = PreviewHostingView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewHostingView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class PreviewHostingView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
#endif
