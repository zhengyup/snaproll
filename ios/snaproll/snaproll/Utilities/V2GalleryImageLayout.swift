import CoreGraphics
import Foundation

enum V2GalleryImageLayout {
    enum Row: Equatable {
        case landscape(Int)
        case portraitPair(Int, Int?)
    }

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

    static func rows(for imageSizes: [CGSize]) -> [Row] {
        var rows: [Row] = []
        var index = 0

        while index < imageSizes.count {
            if isLandscape(imageSizes[index]) {
                rows.append(.landscape(index))
                index += 1
                continue
            }

            if index + 1 < imageSizes.count, !isLandscape(imageSizes[index + 1]) {
                rows.append(.portraitPair(index, index + 1))
                index += 2
            } else {
                rows.append(.portraitPair(index, nil))
                index += 1
            }
        }

        return rows
    }

    static func isLandscape(_ imageSize: CGSize) -> Bool {
        let size = pixelSize(for: imageSize)
        return size.width > size.height
    }
}
