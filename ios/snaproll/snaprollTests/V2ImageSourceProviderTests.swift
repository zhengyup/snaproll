import Foundation
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import snaproll

@MainActor
struct V2ImageSourceProviderTests {
    @Test
    func developmentSampleImageProviderReturnsUsableImageData() async throws {
        let provider = DevelopmentSampleImageSourceProvider()

        let payload = try await provider.captureImage()

        #expect(payload.fileExtension == "png")
        #expect(!payload.data.isEmpty)
        #if canImport(UIKit)
        #expect(UIImage(data: payload.data) != nil)
        #endif
    }
}
