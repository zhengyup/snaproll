import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import snaproll

@MainActor
struct PhotoOrientationTests {
    @Test
    func deviceOrientationMappingRetainsOnlySupportedCaptureOrientations() {
        #expect(CaptureDeviceOrientation.validOrientation(from: .portrait) == .portrait)
        #expect(CaptureDeviceOrientation.validOrientation(from: .landscapeLeft) == .landscapeLeft)
        #expect(CaptureDeviceOrientation.validOrientation(from: .landscapeRight) == .landscapeRight)
        #expect(CaptureDeviceOrientation.validOrientation(from: .faceUp) == nil)
        #expect(CaptureDeviceOrientation.validOrientation(from: .faceDown) == nil)
        #expect(CaptureDeviceOrientation.validOrientation(from: .unknown) == nil)
    }

    @Test
    func normalizesUpDownLeftAndRightToUpOrientation() throws {
        for orientation in [UIImage.Orientation.up, .down, .left, .right] {
            let image = orientedImage(
                pixelSize: CGSize(width: 40, height: 80),
                orientation: orientation
            )

            let normalized = try ImageOrientationNormalizer.normalizedImage(from: image)

            #expect(normalized.imageOrientation == .up)
        }
    }

    @Test
    func portraitOutputRemainsTallerThanWide() throws {
        let portrait = orientedImage(
            pixelSize: CGSize(width: 40, height: 80),
            orientation: .up
        )

        let normalized = try ImageOrientationNormalizer.normalizedImage(from: portrait)

        #expect(normalized.size.height > normalized.size.width)
    }

    @Test
    func landscapeOutputBecomesWiderThanTallAfterRightOrientationNormalization() throws {
        let rotatedLandscape = orientedImage(
            pixelSize: CGSize(width: 40, height: 80),
            orientation: .right
        )

        let normalized = try ImageOrientationNormalizer.normalizedImage(from: rotatedLandscape)

        #expect(normalized.size.width > normalized.size.height)
    }

    @Test
    func normalizationFailureThrowsForImageWithoutCGImage() {
        let image = UIImage()

        #expect(throws: PhotoStorageServiceError.self) {
            _ = try ImageOrientationNormalizer.normalizedImage(from: image)
        }
    }

    @Test
    func savedLocalOriginalIsUprightJPEG() throws {
        let storageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = PhotoStorageService(storageRootDirectoryURL: storageRoot)
        let inputData = try jpegDataWithExifOrientation(
            pixelSize: CGSize(width: 40, height: 80),
            orientation: .right
        )

        let savedURL = try storage.saveOriginalImageData(
            inputData,
            for: UUID(),
            exposureID: UUID(),
            preferredFileExtension: "jpg"
        )
        let savedData = try Data(contentsOf: savedURL)
        let savedImage = try #require(UIImage(data: savedData))

        #expect(savedData.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(savedImage.imageOrientation == .up)
        #expect(savedImage.size.width > savedImage.size.height)
    }

    @Test
    func uploadJPEGUsesNormalizedLocalOriginalWithoutReencodingWhenAlreadyJPEGUp() throws {
        let storageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = PhotoStorageService(storageRootDirectoryURL: storageRoot)
        let image = orientedImage(
            pixelSize: CGSize(width: 80, height: 40),
            orientation: .up
        )
        let inputData = try #require(image.jpegData(compressionQuality: 0.95))
        let savedURL = try storage.saveOriginalImageData(
            inputData,
            for: UUID(),
            exposureID: UUID(),
            preferredFileExtension: "jpg"
        )
        let localPath = storage.persistentLocalPath(for: savedURL)

        let uploadData = try storage.makeUploadJPEGData(from: localPath)

        #expect(uploadData == inputData)
    }

    private func orientedImage(
        pixelSize: CGSize,
        orientation: UIImage.Orientation
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let image = renderer.image { context in
            UIColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: pixelSize))
            UIColor(red: 0.1, green: 0.25, blue: 0.9, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: pixelSize.width / 2, height: pixelSize.height / 3))
        }

        guard let cgImage = image.cgImage else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    private func jpegDataWithExifOrientation(
        pixelSize: CGSize,
        orientation: CGImagePropertyOrientation
    ) throws -> Data {
        let image = orientedImage(pixelSize: pixelSize, orientation: .up)
        let cgImage = try #require(image.cgImage)
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        let properties = [
            kCGImagePropertyOrientation: orientation.rawValue
        ] as CFDictionary

        CGImageDestinationAddImage(destination, cgImage, properties)
        let finalized = CGImageDestinationFinalize(destination)
        #expect(finalized)

        return data as Data
    }
}
