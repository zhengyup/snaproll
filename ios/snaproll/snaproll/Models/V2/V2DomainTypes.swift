import Foundation

enum V2Domain {
    enum RollType: String, Codable, CaseIterable, Sendable {
        case personal = "PERSONAL"
        case shared = "SHARED"
    }

    enum RollStatus: String, Codable, CaseIterable, Sendable {
        case draft = "DRAFT"
        case waitingForParticipants = "WAITING_FOR_PARTICIPANTS"
        case shooting = "SHOOTING"
        case readyToReveal = "READY_TO_REVEAL"
        case revealed = "REVEALED"
    }

    enum ParticipantStatus: String, Codable, CaseIterable, Sendable {
        case joined = "JOINED"
        case shooting = "SHOOTING"
        case finished = "FINISHED"
    }

    enum ExposureSyncState: String, Codable, CaseIterable, Sendable {
        case empty = "EMPTY"
        case localOnly = "LOCAL_ONLY"
        case uploading = "UPLOADING"
        case metadataPending = "METADATA_PENDING"
        case synced = "SYNCED"
        case failed = "FAILED"
    }
}

