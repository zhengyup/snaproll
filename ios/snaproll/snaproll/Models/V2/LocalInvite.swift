import Foundation

#if canImport(SwiftData) && V2_SWIFTDATA_MODELS
import SwiftData

@Model
final class LocalInvite {
    @Attribute(.unique) var id: UUID
    var roll_id: UUID
    var token: String
    var is_active: Bool
    var created_at: Date

    init(
        id: UUID,
        roll_id: UUID,
        token: String,
        is_active: Bool,
        created_at: Date
    ) {
        self.id = id
        self.roll_id = roll_id
        self.token = token
        self.is_active = is_active
        self.created_at = created_at
    }
}
#else
final class LocalInvite {
    var id: UUID
    var roll_id: UUID
    var token: String
    var is_active: Bool
    var created_at: Date

    init(
        id: UUID,
        roll_id: UUID,
        token: String,
        is_active: Bool,
        created_at: Date
    ) {
        self.id = id
        self.roll_id = roll_id
        self.token = token
        self.is_active = is_active
        self.created_at = created_at
    }
}
#endif
