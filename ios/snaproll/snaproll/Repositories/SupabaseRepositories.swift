import Foundation
import OSLog
import Supabase

actor V2SupabaseClientProvider {
    private let configurationLoader: @Sendable () throws -> V2SupabaseConfiguration
    private var cachedClient: SupabaseClient?

    init(
        configurationLoader: @escaping @Sendable () throws -> V2SupabaseConfiguration = {
            try V2SupabaseConfiguration.loadDefault()
        }
    ) {
        self.configurationLoader = configurationLoader
    }

    func client() throws -> SupabaseClient {
        if let cachedClient {
            return cachedClient
        }

        let configuration = try configurationLoader()
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pzy.snaproll",
            category: "Supabase"
        )
        let client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: .init(
                global: .init(
                    logger: OSLogSupabaseLogger(logger)
                )
            )
        )

        cachedClient = client
        return client
    }
}

private enum RepositoryLogger {
    static func logger(category: String) -> Logger {
        Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pzy.snaproll",
            category: category
        )
    }
}

private enum V2RepositoryErrorMapper {
    static func map(_ error: Error) -> V2RepositoryError {
        if let repositoryError = error as? V2RepositoryError {
            return repositoryError
        }

        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "28000":
                return .authenticationRequired
            case "42501":
                return .forbidden(postgrestError.message)
            case "P0002":
                return .notFound(postgrestError.message)
            case "23505":
                return .conflict(postgrestError.message)
            case "22023":
                return .invalidInput(postgrestError.message)
            case "55000":
                return .lifecycleViolation(postgrestError.message)
            case "P0001":
                return .businessRuleViolation(postgrestError.message)
            default:
                return .unknown(postgrestError.message)
            }
        }

        if let urlError = error as? URLError {
            return .network(urlError.localizedDescription)
        }

        if let decodingError = error as? DecodingError {
            return .decoding(String(describing: decodingError))
        }

        return .unknown(error.localizedDescription)
    }
}

private struct SupabaseRollRecord: Decodable {
    let id: UUID
    let title: String
    let type: String
    let status: String
    let film_stock_id: String
    let exposures_per_participant: Int
    let creator_id: UUID
    let created_at: Date
    let started_at: Date?
    let ready_to_reveal_at: Date?
    let revealed_at: Date?
}

private struct SupabaseParticipantRecord: Decodable {
    struct ProfileRecord: Decodable {
        let display_name: String?
    }

    let id: UUID
    let roll_id: UUID
    let user_id: UUID
    let status: String
    let joined_at: Date
    let finished_at: Date?
    let profile: ProfileRecord?
}

private struct SupabaseExposureRecord: Decodable {
    let id: UUID
    let roll_id: UUID
    let participant_id: UUID
    let exposure_number: Int
    let render_seed: String
    let storage_path: String?
    let captured_at: Date?
    let uploaded_at: Date?
    let created_at: Date
}

private struct SupabaseInviteRecord: Decodable {
    let id: UUID
    let roll_id: UUID
    let token: String
    let is_active: Bool
    let created_at: Date
}

private struct CreateRollRPCResponse: Decodable {
    let roll_id: UUID
    let invite_token: String?
}

private struct CreateRollRPCRequest: Encodable {
    let p_title: String
    let p_type: String
    let p_film_stock_id: String
    let p_exposures_per_participant: Int
    let p_participant_cap: Int
}

private struct JoinRollRPCResponse: Decodable {
    let roll_id: UUID
    let participant_id: UUID
}

private struct JoinRollRPCRequest: Encodable {
    let p_invite_token: String
}

private struct RollIDRPCRequest: Encodable {
    let p_roll_id: UUID
}

private struct ProfileDisplayNameRecord: Decodable {
    let display_name: String?
}

private extension SupabaseRollRecord {
    func toLocalRoll(lastSyncedAt: Date = .now) -> LocalRoll {
        LocalRoll(
            id: id,
            title: title,
            type: V2Domain.RollType(rawValue: type) ?? .personal,
            status: V2Domain.RollStatus(rawValue: status) ?? .draft,
            film_stock_id: film_stock_id,
            exposures_per_participant: exposures_per_participant,
            creator_id: creator_id,
            created_at: created_at,
            started_at: started_at,
            ready_to_reveal_at: ready_to_reveal_at,
            revealed_at: revealed_at,
            last_synced_at: lastSyncedAt
        )
    }
}

private extension SupabaseParticipantRecord {
    func toLocalParticipant() -> LocalParticipant {
        LocalParticipant(
            id: id,
            roll_id: roll_id,
            user_id: user_id,
            display_name: profile?.display_name,
            status: V2Domain.ParticipantStatus(rawValue: status) ?? .joined,
            joined_at: joined_at,
            finished_at: finished_at
        )
    }
}

private extension SupabaseExposureRecord {
    func toLocalExposure() -> LocalExposure {
        let syncState: V2Domain.ExposureSyncState = storage_path == nil ? .empty : .synced
        let updatedAt = uploaded_at ?? captured_at ?? created_at

        return LocalExposure(
            id: id,
            roll_id: roll_id,
            participant_id: participant_id,
            exposure_number: exposure_number,
            render_seed: render_seed,
            local_original_path: nil,
            upload_jpeg_path: nil,
            cloud_storage_path: storage_path,
            rendered_cache_path: nil,
            sync_state: syncState,
            captured_at: captured_at,
            uploaded_at: uploaded_at,
            last_error: nil,
            updated_at: updatedAt
        )
    }
}

private extension SupabaseInviteRecord {
    func toLocalInvite() -> LocalInvite {
        LocalInvite(
            id: id,
            roll_id: roll_id,
            token: token,
            is_active: is_active,
            created_at: created_at
        )
    }
}

private protocol SupabaseRepositorySupporting {
    var clientProvider: V2SupabaseClientProvider { get }
    var logger: Logger { get }
}

private extension SupabaseRepositorySupporting {
    func withClient<T>(
        operation: StaticString,
        _ work: (SupabaseClient) async throws -> T
    ) async throws -> T {
        do {
            logger.debug("Starting \(String(describing: operation), privacy: .public)")
            let client = try await clientProvider.client()
            let result = try await work(client)
            logger.debug("Finished \(String(describing: operation), privacy: .public)")
            return result
        } catch {
            let mappedError = V2RepositoryErrorMapper.map(error)
            logger.error(
                "Failed \(String(describing: operation), privacy: .public): \(mappedError.localizedDescription, privacy: .public)"
            )
            throw mappedError
        }
    }
}

final class SupabaseAuthRepository: AuthRepository, @unchecked Sendable, SupabaseRepositorySupporting {
    let clientProvider: V2SupabaseClientProvider
    let logger = RepositoryLogger.logger(category: "V2AuthRepository")

    init(clientProvider: V2SupabaseClientProvider) {
        self.clientProvider = clientProvider
    }

    func currentSession() async throws -> AuthSession? {
        try await withClient(operation: "auth.currentSession") { client in
            guard let session = client.auth.currentSession else {
                return nil
            }

            let profileRows: [ProfileDisplayNameRecord] = try await client
                .from("profiles")
                .select("display_name")
                .eq("id", value: session.user.id)
                .limit(1)
                .execute()
                .value

            return AuthSession(
                userID: session.user.id,
                displayName: profileRows.first?.display_name
            )
        }
    }

    func currentUserID() async throws -> UUID? {
        try await withClient(operation: "auth.currentUserID") { client in
            client.auth.currentSession?.user.id
        }
    }

    func signOut() async throws {
        _ = try await withClient(operation: "auth.signOut") { client in
            try await client.auth.signOut()
        }
    }
}

final class SupabaseRollRepository: RollRepository, @unchecked Sendable, SupabaseRepositorySupporting {
    let clientProvider: V2SupabaseClientProvider
    let logger = RepositoryLogger.logger(category: "V2RollRepository")

    init(clientProvider: V2SupabaseClientProvider) {
        self.clientProvider = clientProvider
    }

    func fetchRoll(id: UUID) async throws -> LocalRoll? {
        try await withClient(operation: "roll.fetchRoll") { client in
            let rows: [SupabaseRollRecord] = try await client
                .from("rolls")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value

            return rows.first?.toLocalRoll()
        }
    }

    func fetchRolls() async throws -> [LocalRoll] {
        try await withClient(operation: "roll.fetchRolls") { client in
            let rows: [SupabaseRollRecord] = try await client
                .from("rolls")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value

            return rows.map { $0.toLocalRoll() }
        }
    }

    func createRoll(
        title: String,
        type: V2Domain.RollType,
        filmStockID: String,
        exposuresPerParticipant: Int,
        participantCap: Int
    ) async throws -> CreateRollResult {
        try await withClient(operation: "roll.createRoll") { client in
            let response: CreateRollRPCResponse = try await client
                .rpc(
                    "create_roll",
                    params: CreateRollRPCRequest(
                        p_title: title,
                        p_type: type.rawValue,
                        p_film_stock_id: filmStockID,
                        p_exposures_per_participant: exposuresPerParticipant,
                        p_participant_cap: participantCap
                    )
                )
                .single()
                .execute()
                .value

            return CreateRollResult(
                rollID: response.roll_id,
                inviteToken: response.invite_token
            )
        }
    }

    func startRoll(id: UUID) async throws {
        _ = try await withClient(operation: "roll.startRoll") { client in
            try await client
                .rpc("start_roll", params: RollIDRPCRequest(p_roll_id: id))
                .execute()
        }
    }

    func saveRoll(_ roll: LocalRoll) async throws {
        throw V2RepositoryError.unsupportedOperation(
            "saveRoll(_:) is deferred until the local SwiftData write path is integrated."
        )
    }

    func deleteRoll(id: UUID) async throws {
        throw V2RepositoryError.unsupportedOperation(
            "deleteRoll(id:) is deferred until the dedicated V2 delete flow is implemented."
        )
    }
}

final class SupabaseParticipantRepository: ParticipantRepository, @unchecked Sendable, SupabaseRepositorySupporting {
    let clientProvider: V2SupabaseClientProvider
    let logger = RepositoryLogger.logger(category: "V2ParticipantRepository")

    init(clientProvider: V2SupabaseClientProvider) {
        self.clientProvider = clientProvider
    }

    func fetchParticipants(forRollID rollID: UUID) async throws -> [LocalParticipant] {
        try await withClient(operation: "participant.fetchParticipants") { client in
            let rows: [SupabaseParticipantRecord] = try await client
                .from("roll_participants")
                .select(
                    """
                    id,
                    roll_id,
                    user_id,
                    status,
                    joined_at,
                    finished_at,
                    profile:user_id (
                      display_name
                    )
                    """
                )
                .eq("roll_id", value: rollID)
                .order("joined_at", ascending: true)
                .execute()
                .value

            return rows.map { $0.toLocalParticipant() }
        }
    }

    func fetchParticipant(id: UUID) async throws -> LocalParticipant? {
        try await withClient(operation: "participant.fetchParticipant") { client in
            let rows: [SupabaseParticipantRecord] = try await client
                .from("roll_participants")
                .select(
                    """
                    id,
                    roll_id,
                    user_id,
                    status,
                    joined_at,
                    finished_at,
                    profile:user_id (
                      display_name
                    )
                    """
                )
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value

            return rows.first?.toLocalParticipant()
        }
    }

    func joinRoll(inviteToken: String) async throws -> JoinRollResult {
        try await withClient(operation: "participant.joinRoll") { client in
            let response: JoinRollRPCResponse = try await client
                .rpc(
                    "join_roll",
                    params: JoinRollRPCRequest(p_invite_token: inviteToken)
                )
                .single()
                .execute()
                .value

            return JoinRollResult(
                rollID: response.roll_id,
                participantID: response.participant_id
            )
        }
    }

    func leaveRoll(rollID: UUID) async throws {
        _ = try await withClient(operation: "participant.leaveRoll") { client in
            try await client
                .rpc("leave_roll", params: RollIDRPCRequest(p_roll_id: rollID))
                .execute()
        }
    }

    func saveParticipant(_ participant: LocalParticipant) async throws {
        throw V2RepositoryError.unsupportedOperation(
            "saveParticipant(_:) is deferred until the local SwiftData write path is integrated."
        )
    }

    func deleteParticipant(id: UUID) async throws {
        throw V2RepositoryError.unsupportedOperation(
            "deleteParticipant(id:) is deferred until the dedicated V2 participant-management flow is implemented."
        )
    }
}

final class SupabaseExposureRepository: ExposureRepository, @unchecked Sendable, SupabaseRepositorySupporting {
    let clientProvider: V2SupabaseClientProvider
    let logger = RepositoryLogger.logger(category: "V2ExposureRepository")

    init(clientProvider: V2SupabaseClientProvider) {
        self.clientProvider = clientProvider
    }

    func fetchExposures(forRollID rollID: UUID) async throws -> [LocalExposure] {
        try await withClient(operation: "exposure.fetchExposuresByRoll") { client in
            let rows: [SupabaseExposureRecord] = try await client
                .from("exposures")
                .select()
                .eq("roll_id", value: rollID)
                .order("exposure_number", ascending: true)
                .execute()
                .value

            return rows.map { $0.toLocalExposure() }
        }
    }

    func fetchExposures(forParticipantID participantID: UUID) async throws -> [LocalExposure] {
        try await withClient(operation: "exposure.fetchExposuresByParticipant") { client in
            let rows: [SupabaseExposureRecord] = try await client
                .from("exposures")
                .select()
                .eq("participant_id", value: participantID)
                .order("exposure_number", ascending: true)
                .execute()
                .value

            return rows.map { $0.toLocalExposure() }
        }
    }

    func fetchExposure(id: UUID) async throws -> LocalExposure? {
        try await withClient(operation: "exposure.fetchExposure") { client in
            let rows: [SupabaseExposureRecord] = try await client
                .from("exposures")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value

            return rows.first?.toLocalExposure()
        }
    }

    func saveExposure(_ exposure: LocalExposure) async throws {
        throw V2RepositoryError.unsupportedOperation(
            "saveExposure(_:) is deferred until the sync engine and local SwiftData write path are implemented."
        )
    }

    func saveExposures(_ exposures: [LocalExposure]) async throws {
        throw V2RepositoryError.unsupportedOperation(
            "saveExposures(_:) is deferred until the sync engine and local SwiftData write path are implemented."
        )
    }
}

final class SupabaseInviteRepository: InviteRepository, @unchecked Sendable, SupabaseRepositorySupporting {
    let clientProvider: V2SupabaseClientProvider
    let logger = RepositoryLogger.logger(category: "V2InviteRepository")

    init(clientProvider: V2SupabaseClientProvider) {
        self.clientProvider = clientProvider
    }

    func fetchInvite(forRollID rollID: UUID) async throws -> LocalInvite? {
        try await withClient(operation: "invite.fetchInviteByRoll") { client in
            let rows: [SupabaseInviteRecord] = try await client
                .from("invites")
                .select()
                .eq("roll_id", value: rollID)
                .eq("is_active", value: true)
                .is("revoked_at", value: nil)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            return rows.first?.toLocalInvite()
        }
    }

    func fetchInvite(token: String) async throws -> LocalInvite? {
        try await withClient(operation: "invite.fetchInviteByToken") { client in
            let rows: [SupabaseInviteRecord] = try await client
                .from("invites")
                .select()
                .eq("token", value: token)
                .limit(1)
                .execute()
                .value

            return rows.first?.toLocalInvite()
        }
    }

    func regenerateInvite(forRollID rollID: UUID) async throws -> LocalInvite {
        try await withClient(operation: "invite.regenerateInvite") { client in
            let token: String = try await client
                .rpc("regenerate_invite", params: RollIDRPCRequest(p_roll_id: rollID))
                .execute()
                .value

            if let invite = try await fetchInvite(token: token) {
                return invite
            }

            throw V2RepositoryError.notFound(
                "The regenerated invite could not be fetched."
            )
        }
    }

    func saveInvite(_ invite: LocalInvite) async throws {
        throw V2RepositoryError.unsupportedOperation(
            "saveInvite(_:) is deferred until the local SwiftData write path is integrated."
        )
    }

    func deleteInvite(id: UUID) async throws {
        throw V2RepositoryError.unsupportedOperation(
            "deleteInvite(id:) is deferred until the dedicated V2 invite-management flow is implemented."
        )
    }
}
