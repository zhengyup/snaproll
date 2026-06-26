import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct RenderTestImagesTool {
    static func main() throws {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let testImagesDirectory = rootURL.appendingPathComponent("test-images", isDirectory: true)
        let outputDirectory = rootURL.appendingPathComponent("render-output", isDirectory: true)
        let contactSheetsDirectory = outputDirectory.appendingPathComponent("contact-sheets", isDirectory: true)

        let renderer = PhotoRenderService()

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: contactSheetsDirectory, withIntermediateDirectories: true)

        let testImages = try fileManager.contentsOfDirectory(at: testImagesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath == false }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        guard !testImages.isEmpty else {
            print("No test images found in \(testImagesDirectory.path)")
            return
        }

        for imageURL in testImages {
            guard let originalCGImage = loadCGImage(from: imageURL) else {
                print("Skipping unreadable image: \(imageURL.lastPathComponent)")
                continue
            }

            let imageName = imageURL.deletingPathExtension().lastPathComponent
            let safeFolderName = sanitizedName(imageName)
            let imageOutputDirectory = outputDirectory.appendingPathComponent(safeFolderName, isDirectory: true)
            try fileManager.createDirectory(at: imageOutputDirectory, withIntermediateDirectories: true)

            let originalOutputURL = imageOutputDirectory.appendingPathComponent("original.jpg")
            let kodakOutputURL = imageOutputDirectory.appendingPathComponent("kodak-gold.jpg")
            let superiaOutputURL = imageOutputDirectory.appendingPathComponent("fujifilm-superia.jpg")

            try writeJPEG(originalCGImage, to: originalOutputURL)

            guard let kodakCGImage = renderer.renderedCGImage(
                for: originalCGImage,
                filmStock: .kodakGold200,
                cacheKey: "\(imageURL.path)::kodak-gold"
            ) else {
                print("Failed Kodak Gold render for \(imageURL.lastPathComponent)")
                continue
            }

            guard let superiaCGImage = renderer.renderedCGImage(
                for: originalCGImage,
                filmStock: .fujifilmSuperia400,
                cacheKey: "\(imageURL.path)::fujifilm-superia"
            ) else {
                print("Failed Fujifilm Superia render for \(imageURL.lastPathComponent)")
                continue
            }

            try writeJPEG(kodakCGImage, to: kodakOutputURL)
            try writeJPEG(superiaCGImage, to: superiaOutputURL)

            let contactSheetURL = contactSheetsDirectory.appendingPathComponent("\(safeFolderName).jpg")
            try makeContactSheet(
                original: originalCGImage,
                kodak: kodakCGImage,
                superia: superiaCGImage,
                title: imageName,
                destinationURL: contactSheetURL
            )

            print("Rendered \(imageURL.lastPathComponent)")
        }

        print("Render output saved to \(outputDirectory.path)")
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RenderToolError.failedToCreateDestination(url.path)
        }

        let options: CFDictionary = [
            kCGImageDestinationLossyCompressionQuality: 0.94
        ] as CFDictionary

        CGImageDestinationAddImage(destination, image, options)

        guard CGImageDestinationFinalize(destination) else {
            throw RenderToolError.failedToWrite(url.path)
        }
    }

    private static func makeContactSheet(
        original: CGImage,
        kodak: CGImage,
        superia: CGImage,
        title: String,
        destinationURL: URL
    ) throws {
        let images = [original, kodak, superia]
        let labels = ["Original", "Kodak Gold 200", "Fujifilm Superia 400"]

        let canvasWidth: CGFloat = 1800
        let headerHeight: CGFloat = 84
        let labelHeight: CGFloat = 40
        let outerPadding: CGFloat = 32
        let interColumnSpacing: CGFloat = 18
        let imageAreaWidth = canvasWidth - (outerPadding * 2) - (interColumnSpacing * 2)
        let columnWidth = imageAreaWidth / 3

        let firstImage = images[0]
        let aspectRatio = CGFloat(firstImage.height) > 0 ? CGFloat(firstImage.width) / CGFloat(firstImage.height) : 1
        let targetImageHeight = min(820, columnWidth / max(aspectRatio, 0.2))
        let canvasHeight = headerHeight + labelHeight + targetImageHeight + outerPadding * 2

        let canvasSize = NSSize(width: canvasWidth, height: canvasHeight)
        let canvasImage = NSImage(size: canvasSize)

        canvasImage.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1.0)
        ]

        let titleString = NSAttributedString(string: title, attributes: titleAttributes)
        titleString.draw(at: NSPoint(x: outerPadding, y: canvasHeight - outerPadding - 28))

        for (index, image) in images.enumerated() {
            let x = outerPadding + CGFloat(index) * (columnWidth + interColumnSpacing)
            let labelRect = NSRect(
                x: x,
                y: canvasHeight - headerHeight - labelHeight,
                width: columnWidth,
                height: labelHeight
            )

            let labelString = NSAttributedString(string: labels[index], attributes: subtitleAttributes)
            labelString.draw(in: labelRect)

            let fittedRect = fittedImageRect(
                image: image,
                frame: NSRect(
                    x: x,
                    y: outerPadding,
                    width: columnWidth,
                    height: targetImageHeight
                )
            )

            NSColor(calibratedWhite: 0.08, alpha: 1.0).setFill()
            NSBezierPath(roundedRect: NSRect(
                x: x,
                y: outerPadding,
                width: columnWidth,
                height: targetImageHeight
            ), xRadius: 8, yRadius: 8).fill()

            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: image, size: .zero).draw(in: fittedRect)
        }

        canvasImage.unlockFocus()

        guard let tiffData = canvasImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
            throw RenderToolError.failedToWrite(destinationURL.path)
        }

        try jpegData.write(to: destinationURL, options: .atomic)
    }

    private static func fittedImageRect(image: CGImage, frame: NSRect) -> NSRect {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else {
            return frame
        }

        let imageAspect = width / height
        let frameAspect = frame.width / frame.height

        if imageAspect > frameAspect {
            let fittedHeight = frame.width / imageAspect
            return NSRect(
                x: frame.minX,
                y: frame.minY + (frame.height - fittedHeight) / 2,
                width: frame.width,
                height: fittedHeight
            )
        } else {
            let fittedWidth = frame.height * imageAspect
            return NSRect(
                x: frame.minX + (frame.width - fittedWidth) / 2,
                y: frame.minY,
                width: fittedWidth,
                height: frame.height
            )
        }
    }

    private static func sanitizedName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return name
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .replacingOccurrences(of: "--", with: "-")
    }
}

enum RenderToolError: Error, CustomStringConvertible {
    case failedToCreateDestination(String)
    case failedToWrite(String)

    var description: String {
        switch self {
        case .failedToCreateDestination(let path):
            return "Could not create image destination at \(path)"
        case .failedToWrite(let path):
            return "Could not write image at \(path)"
        }
    }
}
