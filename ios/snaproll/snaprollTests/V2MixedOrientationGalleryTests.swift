import Testing
import UIKit
@testable import snaproll

@MainActor
struct V2MixedOrientationGalleryTests {
    @Test
    func rendererPreservesPortraitAspectRatioAndReturnsUprightImage() {
        let renderer = PhotoRenderService()
        let image = makeMixedOrientationImage(
            pixelSize: CGSize(width: 80, height: 140),
            orientation: .up
        )

        let rendered = renderer.renderedImage(
            for: image,
            filmStock: .kodakGold200,
            cacheKey: "portrait-\(UUID().uuidString)"
        )

        #expect(rendered.imageOrientation == .up)
        #expect(rendered.size.height > rendered.size.width)
    }

    @Test
    func rendererPreservesLandscapeAspectRatioAndReturnsUprightImage() {
        let renderer = PhotoRenderService()
        let image = makeMixedOrientationImage(
            pixelSize: CGSize(width: 160, height: 90),
            orientation: .up
        )

        let rendered = renderer.renderedImage(
            for: image,
            filmStock: .fujifilmSuperia400,
            cacheKey: "landscape-\(UUID().uuidString)"
        )

        #expect(rendered.imageOrientation == .up)
        #expect(rendered.size.width > rendered.size.height)
    }

    @Test
    func rendererNormalizesLegacyExifOrientationBeforeRendering() {
        let renderer = PhotoRenderService()
        let legacyImage = makeMixedOrientationImage(
            pixelSize: CGSize(width: 80, height: 140),
            orientation: .right
        )

        let rendered = renderer.renderedImage(
            for: legacyImage,
            filmStock: .kodakGold200,
            cacheKey: "legacy-right-\(UUID().uuidString)"
        )

        #expect(rendered.imageOrientation == .up)
        #expect(rendered.size.width > rendered.size.height)
    }

    @Test
    func thumbnailLayoutMakesPortraitCellsTallerThanLandscapeCells() {
        let columnWidth: CGFloat = 160
        let portraitHeight = V2GalleryImageLayout.thumbnailHeight(
            forColumnWidth: columnWidth,
            imageWidth: 90,
            imageHeight: 160
        )
        let landscapeHeight = V2GalleryImageLayout.thumbnailHeight(
            forColumnWidth: columnWidth,
            imageWidth: 160,
            imageHeight: 90
        )

        #expect(portraitHeight > landscapeHeight)
    }

    @Test
    func dimensionHandlingClampsInvalidZeroDimensionsSafely() {
        let size = V2GalleryImageLayout.pixelSize(for: .zero)

        #expect(size.width == 1)
        #expect(size.height == 1)
        #expect(V2GalleryImageLayout.aspectRatio(width: size.width, height: size.height) == 1)
    }

    @Test
    func fullscreenFitUsesOriginalAspectRatio() {
        let portraitRatio = V2GalleryImageLayout.aspectRatio(width: 90, height: 160)
        let landscapeRatio = V2GalleryImageLayout.aspectRatio(width: 160, height: 90)

        #expect(portraitRatio < 1)
        #expect(landscapeRatio > 1)
    }

    private func makeMixedOrientationImage(
        pixelSize: CGSize,
        orientation: UIImage.Orientation
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let image = renderer.image { context in
            UIColor(red: 0.91, green: 0.31, blue: 0.08, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: pixelSize))
            UIColor(red: 0.1, green: 0.35, blue: 0.9, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: pixelSize.width / 2, height: pixelSize.height / 3))
        }

        guard let cgImage = image.cgImage else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }
}
