import Foundation

#if canImport(SwiftData) && V2_SWIFTDATA_MODELS
import SwiftData

@Model
final class LocalRoll {
    @Attribute(.unique) var id: UUID
    var title: String
    var type: V2Domain.RollType
    var status: V2Domain.RollStatus
    var film_stock_id: String
    var exposures_per_participant: Int
    var creator_id: UUID
    var created_at: Date
    var started_at: Date?
    var ready_to_reveal_at: Date?
    var revealed_at: Date?
    var last_synced_at: Date?

    init(
        id: UUID,
        title: String,
        type: V2Domain.RollType,
        status: V2Domain.RollStatus,
        film_stock_id: String,
        exposures_per_participant: Int,
        creator_id: UUID,
        created_at: Date,
        started_at: Date? = nil,
        ready_to_reveal_at: Date? = nil,
        revealed_at: Date? = nil,
        last_synced_at: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.status = status
        self.film_stock_id = film_stock_id
        self.exposures_per_participant = exposures_per_participant
        self.creator_id = creator_id
        self.created_at = created_at
        self.started_at = started_at
        self.ready_to_reveal_at = ready_to_reveal_at
        self.revealed_at = revealed_at
        self.last_synced_at = last_synced_at
    }
}
#else
final class LocalRoll {
    var id: UUID
    var title: String
    var type: V2Domain.RollType
    var status: V2Domain.RollStatus
    var film_stock_id: String
    var exposures_per_participant: Int
    var creator_id: UUID
    var created_at: Date
    var started_at: Date?
    var ready_to_reveal_at: Date?
    var revealed_at: Date?
    var last_synced_at: Date?

    init(
        id: UUID,
        title: String,
        type: V2Domain.RollType,
        status: V2Domain.RollStatus,
        film_stock_id: String,
        exposures_per_participant: Int,
        creator_id: UUID,
        created_at: Date,
        started_at: Date? = nil,
        ready_to_reveal_at: Date? = nil,
        revealed_at: Date? = nil,
        last_synced_at: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.status = status
        self.film_stock_id = film_stock_id
        self.exposures_per_participant = exposures_per_participant
        self.creator_id = creator_id
        self.created_at = created_at
        self.started_at = started_at
        self.ready_to_reveal_at = ready_to_reveal_at
        self.revealed_at = revealed_at
        self.last_synced_at = last_synced_at
    }
}
#endif
