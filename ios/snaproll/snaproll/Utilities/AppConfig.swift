import Foundation

enum AppConfig {
    enum Rolls {
        // Change this to 24 when Phase 5 development testing is complete.
        static let minimumShotLimit = 3
        static let defaultShotLimit = minimumShotLimit
        static let maximumShotLimit = 72
    }

    enum Photos {
        static let jpegCompressionQuality = 0.82
        static let captureFeedbackDurationNanoseconds: UInt64 = 1_100_000_000
        static let completionDismissDelayNanoseconds: UInt64 = 900_000_000
    }
}
