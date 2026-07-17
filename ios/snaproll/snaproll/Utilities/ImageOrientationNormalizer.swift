import Foundation
import UIKit

enum ImageOrientationNormalizer {
    static func normalizedImage(from image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw PhotoStorageServiceError.normalizationFailed
        }

        if image.imageOrientation == .up {
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
        }

        let outputSize = normalizedSize(for: image)
        let sourceSize = sourceSize(for: image)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let normalized = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.concatenate(transform(for: image, outputSize: outputSize))
            cgContext.draw(cgImage, in: CGRect(origin: .zero, size: sourceSize))
        }

        guard normalized.imageOrientation == .up else {
            throw PhotoStorageServiceError.normalizationFailed
        }

        return normalized
    }

    static func normalizedSize(for image: UIImage) -> CGSize {
        guard let cgImage = image.cgImage else {
            return image.size
        }

        let sourceSize = CGSize(
            width: CGFloat(cgImage.width) / image.scale,
            height: CGFloat(cgImage.height) / image.scale
        )

        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: sourceSize.height, height: sourceSize.width)
        case .up, .upMirrored, .down, .downMirrored:
            return sourceSize
        @unknown default:
            return sourceSize
        }
    }

    private static func sourceSize(for image: UIImage) -> CGSize {
        guard let cgImage = image.cgImage else {
            return image.size
        }

        return CGSize(
            width: CGFloat(cgImage.width) / image.scale,
            height: CGFloat(cgImage.height) / image.scale
        )
    }

    private static func transform(for image: UIImage, outputSize: CGSize) -> CGAffineTransform {
        var transform = CGAffineTransform.identity

        switch image.imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: outputSize.width, y: outputSize.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: 0, y: outputSize.height)
            transform = transform.rotated(by: -.pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: outputSize.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .up, .upMirrored:
            break
        @unknown default:
            break
        }

        switch image.imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: image.size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: image.size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        @unknown default:
            break
        }

        return transform
    }
}
