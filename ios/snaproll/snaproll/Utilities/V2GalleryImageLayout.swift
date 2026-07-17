import CoreGraphics
import Foundation

enum V2GalleryImageLayout {
    static func pixelSize(for imageSize: CGSize) -> CGSize {
        CGSize(
            width: max(1, imageSize.width),
            height: max(1, imageSize.height)
        )
    }

    static func aspectRatio(width: CGFloat, height: CGFloat) -> CGFloat {
        max(0.1, width / max(1, height))
    }

    static func thumbnailHeight(forColumnWidth columnWidth: CGFloat, imageWidth: CGFloat, imageHeight: CGFloat) -> CGFloat {
        let ratio = aspectRatio(width: imageWidth, height: imageHeight)
        let rawHeight = columnWidth / ratio
        return min(max(rawHeight, columnWidth * 0.62), columnWidth * 1.55)
    }
}
