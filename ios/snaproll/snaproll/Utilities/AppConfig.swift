import Foundation

enum AppConfig {
    enum Rolls {
        // Development testing shortcut for renderer tuning. Restore this to 24 before release.
        static let minimumShotLimit = 1
        static let defaultShotLimit = minimumShotLimit
        static let maximumShotLimit = 72
    }

    enum Rendering {
        // Set this to false to revert to the Phase 11.3 renderer path.
        static let useBaseFilmResponse = true
    }

    enum Photos {
        static let jpegCompressionQuality = 0.82
        static let captureFeedbackDurationNanoseconds: UInt64 = 1_100_000_000
        static let completionDismissDelayNanoseconds: UInt64 = 900_000_000
    }
}
