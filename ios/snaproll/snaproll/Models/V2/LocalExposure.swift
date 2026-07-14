import Foundation

#if canImport(SwiftData) && V2_SWIFTDATA_MODELS
import SwiftData

@Model
final class LocalExposure {
    @Attribute(.unique) var id: UUID
    var roll_id: UUID
    var participant_id: UUID
    var exposure_number: Int
    var render_seed: String
    var local_original_path: String?
    var upload_jpeg_path: String?
    var cloud_storage_path: String?
    var rendered_cache_path: String?
    var sync_state: V2Domain.ExposureSyncState
    var captured_at: Date?
    var uploaded_at: Date?
    var last_error: String?
    var last_recovery_from_state: String?
    var last_recovery_to_state: String?
    var last_recovery_reason: String?
    var last_recovery_error: String?
    var last_recovered_at: Date?
    var updated_at: Date

    init(
        id: UUID,
        roll_id: UUID,
        participant_id: UUID,
        exposure_number: Int,
        render_seed: String,
        local_original_path: String? = nil,
        upload_jpeg_path: String? = nil,
        cloud_storage_path: String? = nil,
        rendered_cache_path: String? = nil,
        sync_state: V2Domain.ExposureSyncState,
        captured_at: Date? = nil,
        uploaded_at: Date? = nil,
        last_error: String? = nil,
        last_recovery_from_state: String? = nil,
        last_recovery_to_state: String? = nil,
        last_recovery_reason: String? = nil,
        last_recovery_error: String? = nil,
        last_recovered_at: Date? = nil,
        updated_at: Date
    ) {
        self.id = id
        self.roll_id = roll_id
        self.participant_id = participant_id
        self.exposure_number = exposure_number
        self.render_seed = render_seed
        self.local_original_path = local_original_path
        self.upload_jpeg_path = upload_jpeg_path
        self.cloud_storage_path = cloud_storage_path
        self.rendered_cache_path = rendered_cache_path
        self.sync_state = sync_state
        self.captured_at = captured_at
        self.uploaded_at = uploaded_at
        self.last_error = last_error
        self.last_recovery_from_state = last_recovery_from_state
        self.last_recovery_to_state = last_recovery_to_state
        self.last_recovery_reason = last_recovery_reason
        self.last_recovery_error = last_recovery_error
        self.last_recovered_at = last_recovered_at
        self.updated_at = updated_at
    }

    var paddedExposureFilename: String {
        String(format: "%03d.jpg", exposure_number)
    }

    var canonicalCloudStoragePath: String {
        Self.canonicalCloudStoragePath(
            rollID: roll_id,
            participantID: participant_id,
            exposureNumber: exposure_number
        )
    }

    static func canonicalCloudStoragePath(
        rollID: UUID,
        participantID: UUID,
        exposureNumber: Int
    ) -> String {
        let paddedExposureNumber = String(format: "%03d", exposureNumber)
        return "rolls/\(rollID.uuidString.lowercased())/participants/\(participantID.uuidString.lowercased())/\(paddedExposureNumber).jpg"
    }
}
#else
final class LocalExposure {
    var id: UUID
    var roll_id: UUID
    var participant_id: UUID
    var exposure_number: Int
    var render_seed: String
    var local_original_path: String?
    var upload_jpeg_path: String?
    var cloud_storage_path: String?
    var rendered_cache_path: String?
    var sync_state: V2Domain.ExposureSyncState
    var captured_at: Date?
    var uploaded_at: Date?
    var last_error: String?
    var last_recovery_from_state: String?
    var last_recovery_to_state: String?
    var last_recovery_reason: String?
    var last_recovery_error: String?
    var last_recovered_at: Date?
    var updated_at: Date

    init(
        id: UUID,
        roll_id: UUID,
        participant_id: UUID,
        exposure_number: Int,
        render_seed: String,
        local_original_path: String? = nil,
        upload_jpeg_path: String? = nil,
        cloud_storage_path: String? = nil,
        rendered_cache_path: String? = nil,
        sync_state: V2Domain.ExposureSyncState,
        captured_at: Date? = nil,
        uploaded_at: Date? = nil,
        last_error: String? = nil,
        last_recovery_from_state: String? = nil,
        last_recovery_to_state: String? = nil,
        last_recovery_reason: String? = nil,
        last_recovery_error: String? = nil,
        last_recovered_at: Date? = nil,
        updated_at: Date
    ) {
        self.id = id
        self.roll_id = roll_id
        self.participant_id = participant_id
        self.exposure_number = exposure_number
        self.render_seed = render_seed
        self.local_original_path = local_original_path
        self.upload_jpeg_path = upload_jpeg_path
        self.cloud_storage_path = cloud_storage_path
        self.rendered_cache_path = rendered_cache_path
        self.sync_state = sync_state
        self.captured_at = captured_at
        self.uploaded_at = uploaded_at
        self.last_error = last_error
        self.last_recovery_from_state = last_recovery_from_state
        self.last_recovery_to_state = last_recovery_to_state
        self.last_recovery_reason = last_recovery_reason
        self.last_recovery_error = last_recovery_error
        self.last_recovered_at = last_recovered_at
        self.updated_at = updated_at
    }

    var paddedExposureFilename: String {
        String(format: "%03d.jpg", exposure_number)
    }

    var canonicalCloudStoragePath: String {
        Self.canonicalCloudStoragePath(
            rollID: roll_id,
            participantID: participant_id,
            exposureNumber: exposure_number
        )
    }

    static func canonicalCloudStoragePath(
        rollID: UUID,
        participantID: UUID,
        exposureNumber: Int
    ) -> String {
        let paddedExposureNumber = String(format: "%03d", exposureNumber)
        return "rolls/\(rollID.uuidString.lowercased())/participants/\(participantID.uuidString.lowercased())/\(paddedExposureNumber).jpg"
    }
}
#endif
