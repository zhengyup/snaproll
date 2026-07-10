import Foundation

enum V2ExperienceMode {
    case developer
    case user
}

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

    enum V2 {
        // Keep this disabled until V2 auth/session bootstrap is ready for manual rollout.
        static let isSessionBootstrapEnabled = true
        static let storageBucketName = "snaproll-originals"

        #if DEBUG
        // Change only this value to switch between a developer-facing V2 experience and a user-facing one.
        static let experienceMode: V2ExperienceMode = .developer
        // Development-only auth path for building shared-roll features without Apple or Google sign-in.
        static let isDevelopmentAuthenticationEnabled = true
        static let developmentIdentity: DevelopmentAuthIdentity = .creator
        #else
        static let experienceMode: V2ExperienceMode = .user
        static let isDevelopmentAuthenticationEnabled = false
        static let developmentIdentity: DevelopmentAuthIdentity = .creator
        #endif

        static var showsDeveloperUI: Bool {
            #if DEBUG
            return experienceMode == .developer
            #else
            return false
            #endif
        }

        static var isExposureDiagnosticsEnabled: Bool {
            showsDeveloperUI
        }

        static var showsDevelopmentIdentityControls: Bool {
            showsDeveloperUI
        }

        static var navigationTitle: String {
            showsDeveloperUI ? "V2 Cloud Rolls" : "My Rolls"
        }

        static var authenticationMode: V2AuthenticationMode {
            #if DEBUG
            if isDevelopmentAuthenticationEnabled {
                return .development(developmentIdentity)
            }
            #endif

            return .standard
        }
    }
}
