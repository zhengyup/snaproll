import Foundation

struct AuthSession: Sendable, Equatable {
    let userID: UUID
    let displayName: String?
}

struct CreateRollResult: Sendable {
    let rollID: UUID
    let inviteToken: String?
}

struct JoinRollResult: Sendable {
    let rollID: UUID
    let participantID: UUID
}

protocol AuthRepository: Sendable {
    func currentSession() async throws -> AuthSession?
    func currentUserID() async throws -> UUID?
    func signOut() async throws
}

protocol RollRepository: Sendable {
    func fetchRoll(id: UUID) async throws -> LocalRoll?
    func fetchRolls() async throws -> [LocalRoll]
    func fetchAllRolls() async throws -> [LocalRoll]
    func startRoll(id: UUID) async throws
    func createRoll(
        title: String,
        type: V2Domain.RollType,
        filmStockID: String,
        exposuresPerParticipant: Int,
        participantCap: Int
    ) async throws -> CreateRollResult
    func saveRoll(_ roll: LocalRoll) async throws
    func deleteRoll(id: UUID) async throws
}

protocol ParticipantRepository: Sendable {
    func fetchParticipants(forRollID rollID: UUID) async throws -> [LocalParticipant]
    func fetchParticipant(id: UUID) async throws -> LocalParticipant?
    func joinRoll(inviteToken: String) async throws -> JoinRollResult
    func leaveRoll(rollID: UUID) async throws
    func saveParticipant(_ participant: LocalParticipant) async throws
    func deleteParticipant(id: UUID) async throws
}

protocol ExposureRepository: Sendable {
    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure]
    func fetchExposures(forParticipantID participantID: UUID) async throws -> [LocalExposure]
    func fetchExposure(id: UUID) async throws -> LocalExposure?
    func saveExposure(_ exposure: LocalExposure) async throws
    func saveExposures(_ exposures: [LocalExposure]) async throws
}

@MainActor
protocol ExposureMirrorStore: AnyObject {
    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure]
    func mirrorCloudExposures(_ exposures: [LocalExposure], forRollID rollID: UUID) async throws -> [LocalExposure]
}

protocol InviteRepository: Sendable {
    func fetchInvite(forRollID rollID: UUID) async throws -> LocalInvite?
    func fetchInvite(token: String) async throws -> LocalInvite?
    func regenerateInvite(forRollID rollID: UUID) async throws -> LocalInvite
    func saveInvite(_ invite: LocalInvite) async throws
    func deleteInvite(id: UUID) async throws
}

protocol SyncRepository: Sendable {
    func markRollSynced(_ rollID: UUID, at date: Date) async throws
    func markExposureSyncState(
        _ exposureID: UUID,
        state: V2Domain.ExposureSyncState,
        lastError: String?
    ) async throws
    func pendingExposureIDs() async throws -> [UUID]
}

protocol RenderCacheRepository: Sendable {
    func cachedRenderPath(forExposureID exposureID: UUID) async throws -> String?
    func saveRenderedCachePath(_ path: String?, forExposureID exposureID: UUID) async throws
    func clearRenderedCache(forExposureID exposureID: UUID) async throws
}

extension RollRepository {
    func fetchAllRolls() async throws -> [LocalRoll] {
        try await fetchRolls()
    }
}
