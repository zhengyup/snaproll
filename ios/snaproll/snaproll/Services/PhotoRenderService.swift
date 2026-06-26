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

        let profile = filmProfile(for: filmStock)
        let renderedCIImage = render(ciImage, with: profile)

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

    private func render(_ image: CIImage, with profile: FilmProfile) -> CIImage {
        var currentImage = image

        if let monochromeMix = profile.monochromeMix {
            currentImage = applyMonochrome(currentImage, color: monochromeMix.color, intensity: monochromeMix.intensity)
        }

        if let temperature = profile.temperature {
            currentImage = applyTemperature(
                currentImage,
                neutralX: 6500,
                neutralY: 0,
                targetX: temperature.x,
                targetY: temperature.y
            )
        }

        if let colorMatrix = profile.colorMatrix {
            currentImage = applyColorMatrix(
                currentImage,
                red: colorMatrix.red,
                green: colorMatrix.green,
                blue: colorMatrix.blue
            )
        }

        currentImage = applyToneCurve(currentImage, points: profile.toneCurve)
        currentImage = applyHighlightShadow(
            currentImage,
            highlightAmount: profile.highlightAmount,
            shadowAmount: profile.shadowAmount
        )
        currentImage = applyColorControls(
            currentImage,
            saturation: profile.saturation,
            contrast: profile.contrast,
            brightness: profile.brightness
        )
        currentImage = applyNoiseReduction(
            currentImage,
            noiseLevel: profile.noiseReductionLevel,
            sharpness: profile.noiseReductionSharpness
        )
        currentImage = applySubtleSoftening(currentImage, radius: profile.softeningRadius, amount: profile.softeningAmount)
        currentImage = applyShadowWeightedGrain(
            to: currentImage,
            intensity: profile.grainIntensity,
            blurRadius: profile.grainBlurRadius
        )
        return applyVignette(currentImage, intensity: profile.vignetteIntensity, radius: profile.vignetteRadius)
    }

    private func filmProfile(for filmStock: FilmStock) -> FilmProfile {
        switch filmStock {
        case .kodakGold200:
            return FilmProfile(
                temperature: CGPoint(x: 7050, y: 6),
                colorMatrix: ColorMatrixProfile(
                    red: CIVector(x: 1.03, y: 0.02, z: -0.01, w: 0),
                    green: CIVector(x: 0.01, y: 1.01, z: 0.01, w: 0),
                    blue: CIVector(x: 0, y: 0, z: 0.96, w: 0)
                ),
                monochromeMix: nil,
                toneCurve: [
                    CGPoint(x: 0.00, y: 0.02),
                    CGPoint(x: 0.23, y: 0.20),
                    CGPoint(x: 0.52, y: 0.56),
                    CGPoint(x: 0.80, y: 0.84),
                    CGPoint(x: 1.00, y: 0.97)
                ],
                highlightAmount: 0.68,
                shadowAmount: 0.20,
                saturation: 1.05,
                contrast: 1.03,
                brightness: 0.008,
                noiseReductionLevel: 0.014,
                noiseReductionSharpness: 0.12,
                softeningRadius: 0.45,
                softeningAmount: 0.12,
                grainIntensity: 0.020,
                grainBlurRadius: 0.22,
                vignetteIntensity: 0.16,
                vignetteRadius: 0.95
            )
        case .fujifilmSuperia400:
            return FilmProfile(
                temperature: CGPoint(x: 6150, y: -5),
                colorMatrix: ColorMatrixProfile(
                    red: CIVector(x: 0.99, y: 0.01, z: 0, w: 0),
                    green: CIVector(x: 0.01, y: 1.03, z: 0.015, w: 0),
                    blue: CIVector(x: 0, y: 0.015, z: 1.05, w: 0)
                ),
                monochromeMix: nil,
                toneCurve: [
                    CGPoint(x: 0.00, y: 0.05),
                    CGPoint(x: 0.24, y: 0.22),
                    CGPoint(x: 0.50, y: 0.52),
                    CGPoint(x: 0.78, y: 0.79),
                    CGPoint(x: 1.00, y: 0.95)
                ],
                highlightAmount: 0.62,
                shadowAmount: 0.16,
                saturation: 0.99,
                contrast: 1.02,
                brightness: 0.006,
                noiseReductionLevel: 0.016,
                noiseReductionSharpness: 0.10,
                softeningRadius: 0.42,
                softeningAmount: 0.11,
                grainIntensity: 0.017,
                grainBlurRadius: 0.20,
                vignetteIntensity: 0.12,
                vignetteRadius: 0.90
            )
        case .ilfordHP5Plus:
            return FilmProfile(
                temperature: nil,
                colorMatrix: nil,
                monochromeMix: MonochromeProfile(color: CIColor(red: 0.72, green: 0.72, blue: 0.72), intensity: 1.0),
                toneCurve: [
                    CGPoint(x: 0.00, y: 0.00),
                    CGPoint(x: 0.20, y: 0.11),
                    CGPoint(x: 0.49, y: 0.50),
                    CGPoint(x: 0.78, y: 0.84),
                    CGPoint(x: 1.00, y: 0.97)
                ],
                highlightAmount: 0.58,
                shadowAmount: 0.05,
                saturation: 0.0,
                contrast: 1.10,
                brightness: -0.004,
                noiseReductionLevel: 0.012,
                noiseReductionSharpness: 0.08,
                softeningRadius: 0.36,
                softeningAmount: 0.10,
                grainIntensity: 0.030,
                grainBlurRadius: 0.14,
                vignetteIntensity: 0.18,
                vignetteRadius: 0.96
            )
        }
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

    private func applyToneCurve(_ image: CIImage, points: [CGPoint]) -> CIImage {
        guard points.count == 5,
              let filter = CIFilter(name: "CIToneCurve") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: points[0]), forKey: "inputPoint0")
        filter.setValue(CIVector(cgPoint: points[1]), forKey: "inputPoint1")
        filter.setValue(CIVector(cgPoint: points[2]), forKey: "inputPoint2")
        filter.setValue(CIVector(cgPoint: points[3]), forKey: "inputPoint3")
        filter.setValue(CIVector(cgPoint: points[4]), forKey: "inputPoint4")
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

    private func applyMonochrome(_ image: CIImage, color: CIColor, intensity: CGFloat) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMonochrome") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(color, forKey: kCIInputColorKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
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

    private func applySubtleSoftening(_ image: CIImage, radius: CGFloat, amount: CGFloat) -> CIImage {
        guard amount > 0.001,
              let blurFilter = CIFilter(name: "CIGaussianBlur"),
              let blendFilter = CIFilter(name: "CISourceOverCompositing"),
              let alphaFilter = CIFilter(name: "CIColorMatrix") else {
            return image
        }

        blurFilter.setValue(image, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let blurredImage = blurFilter.outputImage?.cropped(to: image.extent) else {
            return image
        }

        alphaFilter.setValue(blurredImage, forKey: kCIInputImageKey)
        alphaFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        alphaFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: amount), forKey: "inputAVector")

        guard let softenedOverlay = alphaFilter.outputImage else {
            return image
        }

        blendFilter.setValue(softenedOverlay, forKey: kCIInputImageKey)
        blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        return blendFilter.outputImage?.cropped(to: image.extent) ?? image
    }

    private func applyShadowWeightedGrain(to image: CIImage, intensity: CGFloat, blurRadius: CGFloat) -> CIImage {
        guard intensity > 0.001,
              let randomGenerator = CIFilter(name: "CIRandomGenerator")?.outputImage,
              let monochromeNoise = CIFilter(name: "CIColorControls"),
              let noiseTone = CIFilter(name: "CIToneCurve"),
              let noiseBlur = CIFilter(name: "CIGaussianBlur"),
              let grayscaleImage = CIFilter(name: "CIColorControls"),
              let invertFilter = CIFilter(name: "CIColorInvert"),
              let maskCurve = CIFilter(name: "CIToneCurve"),
              let alphaFilter = CIFilter(name: "CIColorMatrix"),
              let maskedBlend = CIFilter(name: "CIBlendWithAlphaMask"),
              let overlayBlend = CIFilter(name: "CISoftLightBlendMode") else {
            return image
        }

        let croppedNoise = randomGenerator.cropped(to: image.extent)
        monochromeNoise.setValue(croppedNoise, forKey: kCIInputImageKey)
        monochromeNoise.setValue(0.0, forKey: kCIInputSaturationKey)
        monochromeNoise.setValue(1.0, forKey: kCIInputBrightnessKey)
        monochromeNoise.setValue(1.28, forKey: kCIInputContrastKey)

        guard let monochromeNoiseImage = monochromeNoise.outputImage?.cropped(to: image.extent) else {
            return image
        }

        noiseTone.setValue(monochromeNoiseImage, forKey: kCIInputImageKey)
        noiseTone.setValue(CIVector(cgPoint: CGPoint(x: 0.00, y: 0.42)), forKey: "inputPoint0")
        noiseTone.setValue(CIVector(cgPoint: CGPoint(x: 0.25, y: 0.48)), forKey: "inputPoint1")
        noiseTone.setValue(CIVector(cgPoint: CGPoint(x: 0.50, y: 0.50)), forKey: "inputPoint2")
        noiseTone.setValue(CIVector(cgPoint: CGPoint(x: 0.75, y: 0.52)), forKey: "inputPoint3")
        noiseTone.setValue(CIVector(cgPoint: CGPoint(x: 1.00, y: 0.58)), forKey: "inputPoint4")

        guard let tunedNoise = noiseTone.outputImage?.cropped(to: image.extent) else {
            return image
        }

        noiseBlur.setValue(tunedNoise, forKey: kCIInputImageKey)
        noiseBlur.setValue(blurRadius, forKey: kCIInputRadiusKey)
        let softenedNoise = noiseBlur.outputImage?.cropped(to: image.extent) ?? tunedNoise

        grayscaleImage.setValue(image, forKey: kCIInputImageKey)
        grayscaleImage.setValue(0.0, forKey: kCIInputSaturationKey)
        grayscaleImage.setValue(1.0, forKey: kCIInputContrastKey)
        grayscaleImage.setValue(0.0, forKey: kCIInputBrightnessKey)

        guard let grayscaleBase = grayscaleImage.outputImage?.cropped(to: image.extent) else {
            return image
        }

        invertFilter.setValue(grayscaleBase, forKey: kCIInputImageKey)
        guard let invertedLuminance = invertFilter.outputImage?.cropped(to: image.extent) else {
            return image
        }

        maskCurve.setValue(invertedLuminance, forKey: kCIInputImageKey)
        maskCurve.setValue(CIVector(cgPoint: CGPoint(x: 0.00, y: 0.00)), forKey: "inputPoint0")
        maskCurve.setValue(CIVector(cgPoint: CGPoint(x: 0.20, y: 0.10)), forKey: "inputPoint1")
        maskCurve.setValue(CIVector(cgPoint: CGPoint(x: 0.48, y: 0.72)), forKey: "inputPoint2")
        maskCurve.setValue(CIVector(cgPoint: CGPoint(x: 0.78, y: 0.90)), forKey: "inputPoint3")
        maskCurve.setValue(CIVector(cgPoint: CGPoint(x: 1.00, y: 0.30)), forKey: "inputPoint4")

        guard let grainMask = maskCurve.outputImage?.cropped(to: image.extent) else {
            return image
        }

        alphaFilter.setValue(softenedNoise, forKey: kCIInputImageKey)
        alphaFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        alphaFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: intensity), forKey: "inputAVector")

        guard let alphaNoise = alphaFilter.outputImage?.cropped(to: image.extent) else {
            return image
        }

        let transparentBackground = CIImage(color: .clear).cropped(to: image.extent)

        maskedBlend.setValue(alphaNoise, forKey: kCIInputImageKey)
        maskedBlend.setValue(transparentBackground, forKey: kCIInputBackgroundImageKey)
        maskedBlend.setValue(grainMask, forKey: kCIInputMaskImageKey)

        guard let maskedNoise = maskedBlend.outputImage?.cropped(to: image.extent) else {
            return image
        }

        overlayBlend.setValue(maskedNoise, forKey: kCIInputImageKey)
        overlayBlend.setValue(image, forKey: kCIInputBackgroundImageKey)
        return overlayBlend.outputImage?.cropped(to: image.extent) ?? image
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

private struct FilmProfile {
    let temperature: CGPoint?
    let colorMatrix: ColorMatrixProfile?
    let monochromeMix: MonochromeProfile?
    let toneCurve: [CGPoint]
    let highlightAmount: CGFloat
    let shadowAmount: CGFloat
    let saturation: CGFloat
    let contrast: CGFloat
    let brightness: CGFloat
    let noiseReductionLevel: CGFloat
    let noiseReductionSharpness: CGFloat
    let softeningRadius: CGFloat
    let softeningAmount: CGFloat
    let grainIntensity: CGFloat
    let grainBlurRadius: CGFloat
    let vignetteIntensity: CGFloat
    let vignetteRadius: CGFloat
}

private struct ColorMatrixProfile {
    let red: CIVector
    let green: CIVector
    let blue: CIVector
}

private struct MonochromeProfile {
    let color: CIColor
    let intensity: CGFloat
}
