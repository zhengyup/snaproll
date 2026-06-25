import CoreImage
import Foundation
import UIKit

final class PhotoRenderService {
    private let context = CIContext()
    private let cache = NSCache<NSString, UIImage>()

    func renderedImage(for image: UIImage, filmStock: FilmStock, cacheKey: String) -> UIImage {
        let key = "\(filmStock.rawValue)::\(cacheKey)" as NSString

        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        guard let ciImage = CIImage(image: image) else {
            return image
        }

        let renderedCIImage = render(ciImage, for: filmStock)
        guard let cgImage = context.createCGImage(renderedCIImage, from: renderedCIImage.extent) else {
            return image
        }

        let renderedImage = UIImage(
            cgImage: cgImage,
            scale: image.scale,
            orientation: image.imageOrientation
        )
        cache.setObject(renderedImage, forKey: key)
        return renderedImage
    }

    private func render(_ image: CIImage, for filmStock: FilmStock) -> CIImage {
        switch filmStock {
        case .kodakGold200:
            return renderKodakGold200(image)
        case .fujifilmSuperia400:
            return renderFujifilmSuperia400(image)
        case .ilfordHP5Plus:
            return renderIlfordHP5Plus(image)
        }
    }

    private func renderKodakGold200(_ image: CIImage) -> CIImage {
        let warmed = applyTemperature(image, neutralX: 6500, neutralY: 0, targetX: 7300, targetY: 8)
        let softened = applyHighlightShadow(warmed, highlightAmount: 0.96, shadowAmount: 0.28)
        let colored = applyColorControls(softened, saturation: 1.12, contrast: 1.06, brightness: 0.015)
        return applyVignette(colored, intensity: 0.22, radius: 1.05)
    }

    private func renderFujifilmSuperia400(_ image: CIImage) -> CIImage {
        let cooled = applyTemperature(image, neutralX: 6500, neutralY: 0, targetX: 6100, targetY: -6)
        let tinted = applyColorMatrix(
            cooled,
            red: CIVector(x: 0.99, y: 0.01, z: 0, w: 0),
            green: CIVector(x: 0, y: 1.03, z: 0.02, w: 0),
            blue: CIVector(x: 0, y: 0.01, z: 1.05, w: 0)
        )
        let softenedHighlights = applyHighlightShadow(tinted, highlightAmount: 0.90, shadowAmount: 0.18)
        let contrasted = applyColorControls(softenedHighlights, saturation: 0.98, contrast: 1.07, brightness: 0.012)
        let softened = applyNoiseReduction(contrasted, noiseLevel: 0.01, sharpness: 0.18)
        let grained = applySoftGrain(to: softened, intensity: 0.018)
        return applyVignette(grained, intensity: 0.14, radius: 0.92)
    }

    private func renderIlfordHP5Plus(_ image: CIImage) -> CIImage {
        let monochrome = applyMonochrome(image)
        let contrasted = applyColorControls(monochrome, saturation: 0, contrast: 1.22, brightness: 0.01)
        let shadowLifted = applyHighlightShadow(contrasted, highlightAmount: 0.94, shadowAmount: 0.10)
        let grained = applySoftGrain(to: shadowLifted, intensity: 0.03)
        return applyVignette(grained, intensity: 0.24, radius: 1.00)
    }

    private func applyTemperature(
        _ image: CIImage,
        neutralX: CGFloat,
        neutralY: CGFloat,
        targetX: CGFloat,
        targetY: CGFloat
    ) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: neutralX, y: neutralY), forKey: "inputNeutral")
        filter.setValue(CIVector(x: targetX, y: targetY), forKey: "inputTargetNeutral")
        return filter.outputImage ?? image
    }

    private func applyColorControls(
        _ image: CIImage,
        saturation: CGFloat,
        contrast: CGFloat,
        brightness: CGFloat
    ) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(saturation, forKey: kCIInputSaturationKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        return filter.outputImage ?? image
    }

    private func applyHighlightShadow(
        _ image: CIImage,
        highlightAmount: CGFloat,
        shadowAmount: CGFloat
    ) -> CIImage {
        guard let filter = CIFilter(name: "CIHighlightShadowAdjust") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(highlightAmount, forKey: "inputHighlightAmount")
        filter.setValue(shadowAmount, forKey: "inputShadowAmount")
        return filter.outputImage ?? image
    }

    private func applyColorMatrix(
        _ image: CIImage,
        red: CIVector,
        green: CIVector,
        blue: CIVector
    ) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(red, forKey: "inputRVector")
        filter.setValue(green, forKey: "inputGVector")
        filter.setValue(blue, forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return filter.outputImage ?? image
    }

    private func applyMonochrome(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    private func applyNoiseReduction(_ image: CIImage, noiseLevel: CGFloat, sharpness: CGFloat) -> CIImage {
        guard let filter = CIFilter(name: "CINoiseReduction") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(noiseLevel, forKey: "inputNoiseLevel")
        filter.setValue(sharpness, forKey: "inputSharpness")
        return filter.outputImage ?? image
    }

    private func applySoftGrain(to image: CIImage, intensity: CGFloat) -> CIImage {
        guard let randomGenerator = CIFilter(name: "CIRandomGenerator")?.outputImage,
              let alphaMatrix = CIFilter(name: "CIColorMatrix"),
              let composite = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }

        let croppedNoise = randomGenerator.cropped(to: image.extent)
        alphaMatrix.setValue(croppedNoise, forKey: kCIInputImageKey)
        alphaMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        alphaMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        alphaMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        alphaMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: intensity), forKey: "inputAVector")

        guard let noiseOverlay = alphaMatrix.outputImage else {
            return image
        }

        composite.setValue(noiseOverlay, forKey: kCIInputImageKey)
        composite.setValue(image, forKey: kCIInputBackgroundImageKey)
        return composite.outputImage?.cropped(to: image.extent) ?? image
    }

    private func applyVignette(_ image: CIImage, intensity: CGFloat, radius: CGFloat) -> CIImage {
        guard let filter = CIFilter(name: "CIVignette") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage ?? image
    }
}
