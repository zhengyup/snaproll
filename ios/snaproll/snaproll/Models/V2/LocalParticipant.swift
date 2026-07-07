import Foundation

#if canImport(SwiftData) && V2_SWIFTDATA_MODELS
import SwiftData

@Model
final class LocalParticipant {
    @Attribute(.unique) var id: UUID
    var roll_id: UUID
    var user_id: UUID
    var display_name: String?
    var status: V2Domain.ParticipantStatus
    var joined_at: Date
    var finished_at: Date?

    init(
        id: UUID,
        roll_id: UUID,
        user_id: UUID,
        display_name: String? = nil,
        status: V2Domain.ParticipantStatus,
        joined_at: Date,
        finished_at: Date? = nil
    ) {
        self.id = id
        self.roll_id = roll_id
        self.user_id = user_id
        self.display_name = display_name
        self.status = status
        self.joined_at = joined_at
        self.finished_at = finished_at
    }
}
#else
final class LocalParticipant {
    var id: UUID
    var roll_id: UUID
    var user_id: UUID
    var display_name: String?
    var status: V2Domain.ParticipantStatus
    var joined_at: Date
    var finished_at: Date?

    init(
        id: UUID,
        roll_id: UUID,
        user_id: UUID,
        display_name: String? = nil,
        status: V2Domain.ParticipantStatus,
        joined_at: Date,
        finished_at: Date? = nil
    ) {
        self.id = id
        self.roll_id = roll_id
        self.user_id = user_id
        self.display_name = display_name
        self.status = status
        self.joined_at = joined_at
        self.finished_at = finished_at
    }
}
#endif
