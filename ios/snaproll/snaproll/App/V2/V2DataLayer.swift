#if canImport(SwiftData) && V2_SWIFTDATA_MODELS
import SwiftData

enum V2DataLayer {
    static var schema: Schema {
        Schema([
            LocalRoll.self,
            LocalParticipant.self,
            LocalExposure.self,
            LocalInvite.self
        ])
    }
}
#else
enum V2DataLayer {
}
#endif
