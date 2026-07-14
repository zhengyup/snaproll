import Foundation
import OSLog

@MainActor
final class V2ExposureReconciliationCoordinator: ExposureReconciling {
    private let authRepository: any AuthRepository
    private let rollRepository: any RollRepository
    private let participantRepository: any ParticipantRepository
    private let exposureRepository: any ExposureRepository
    private let exposureMirrorStore: any ExposureMirrorStore
    private let photoStorageService: PhotoStorageService
    private let logger: Logger

    init(
        authRepository: any AuthRepository,
        rollRepository: any RollRepository,
        participantRepository: any ParticipantRepository,
        exposureRepository: any ExposureRepository,
        exposureMirrorStore: any ExposureMirrorStore,
        photoStorageService: PhotoStorageService,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pzy.snaproll",
            category: "V2Reconciliation"
        )
    ) {
        self.authRepository = authRepository
        self.rollRepository = rollRepository
        self.participantRepository = participantRepository
        self.exposureRepository = exposureRepository
        self.exposureMirrorStore = exposureMirrorStore
        self.photoStorageService = photoStorageService
        self.logger = logger
    }

    func reconcileCurrentSession() async {
        do {
            guard try await authRepository.currentSession() != nil else {
                return
            }

            let rolls = try await rollRepository.fetchRolls()
            for roll in rolls {
                try await reconcile(roll: roll)
            }
        } catch {
            logger.error("Session reconciliation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reconcileRoll(id rollID: UUID) async {
        do {
            guard let roll = try await rollRepository.fetchRoll(id: rollID) else {
                return
            }

            try await reconcile(roll: roll)
        } catch {
            logger.error(
                "Roll reconciliation failed for \(rollID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func reconcile(roll: LocalRoll) async throws {
        guard let session = try await authRepository.currentSession() else {
            return
        }

        let participants = try await participantRepository.fetchParticipants(forRollID: roll.id)
        let participantsByID = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
        let currentParticipant = participants.first(where: { $0.user_id == session.userID })

        guard roll.type == .personal || currentParticipant != nil else {
            return
        }

        let cloudExposures: [LocalExposure]
        if let currentParticipant {
            cloudExposures = try await exposureRepository.fetchExposures(forParticipantID: currentParticipant.id)
        } else {
            cloudExposures = try await exposureRepository.fetchExposures(forRollID: roll.id)
        }

        let localExposures = try await exposureMirrorStore.fetchExposures(forRollID: roll.id)
        let localByID = Dictionary(uniqueKeysWithValues: localExposures.map { ($0.id, $0) })
        let cloudIDs = Set(cloudExposures.map(\.id))
        let reconciledAt = Date.now

        for cloudExposure in cloudExposures {
            let participant = participantsByID[cloudExposure.participant_id]
            let ownerUserID = participant?.user_id
            let localExposure = localByID[cloudExposure.id]
            let reconciled = reconcileExposure(
                local: localExposure,
                cloud: cloudExposure,
                ownerUserID: ownerUserID,
                reconciledAt: reconciledAt
            )
            try await exposureMirrorStore.saveExposure(reconciled)
        }

        for localExposure in localExposures where !cloudIDs.contains(localExposure.id) {
            guard shouldInspectUnmatchedLocal(localExposure, currentUserID: session.userID) else {
                continue
            }

            localExposure.last_reconciliation_rule = "LOCAL_EXPOSURE_MISSING_IN_CLOUD"
            localExposure.last_reconciliation_error = "Local exposure has no matching cloud exposure slot."
            localExposure.last_reconciled_at = reconciledAt
            localExposure.updated_at = reconciledAt
            try await exposureMirrorStore.saveExposure(localExposure)
        }
    }

    private func reconcileExposure(
        local: LocalExposure?,
        cloud: LocalExposure,
        ownerUserID: UUID?,
        reconciledAt: Date
    ) -> LocalExposure {
        let exposure = local ?? cloud
        exposure.owner_user_id = ownerUserID ?? exposure.owner_user_id
        exposure.roll_id = cloud.roll_id
        exposure.participant_id = cloud.participant_id
        exposure.exposure_number = cloud.exposure_number
        exposure.render_seed = cloud.render_seed
        exposure.uploaded_at = cloud.uploaded_at ?? exposure.uploaded_at

        let localPath = normalizedPath(exposure.cloud_storage_path)
        let cloudPath = normalizedPath(cloud.cloud_storage_path)
        let localOriginalMissing = isLocalOriginalMissing(exposure)

        exposure.last_reconciled_at = reconciledAt
        exposure.updated_at = reconciledAt

        if let localPath, let cloudPath, localPath != cloudPath {
            exposure.sync_state = .failed
            exposure.last_reconciliation_rule = "PATH_MISMATCH"
            exposure.last_reconciliation_error = "Local and cloud storage paths differ."
            exposure.last_error = "Local and cloud storage paths differ."
            return exposure
        }

        if let cloudPath {
            exposure.cloud_storage_path = cloudPath
            exposure.sync_state = .synced
            exposure.last_error = nil
            exposure.last_reconciliation_rule = local == nil ? "CLOUD_EXPOSURE_CREATED_LOCAL_MIRROR" : "CLOUD_FILLED_SAME_PATH"
            exposure.last_reconciliation_error = localOriginalMissing ? "Local original is missing; cloud metadata is preserved." : nil
            return exposure
        }

        switch exposure.sync_state {
        case .metadataPending:
            exposure.last_reconciliation_rule = "METADATA_PENDING_CLOUD_EMPTY"
            exposure.last_reconciliation_error = localOriginalMissing ? "Local original is missing while metadata is pending." : nil
        case .localOnly, .uploading:
            exposure.sync_state = .localOnly
            exposure.last_reconciliation_rule = "LOCAL_RETRY_CLOUD_EMPTY"
            exposure.last_reconciliation_error = localOriginalMissing ? "Local original is missing; upload cannot proceed." : nil
            if localOriginalMissing {
                exposure.sync_state = .failed
                exposure.last_error = "Local original is missing; upload cannot proceed."
            }
        case .failed:
            exposure.sync_state = normalizedPath(exposure.cloud_storage_path) == nil ? .localOnly : .metadataPending
            exposure.last_reconciliation_rule = "FAILED_RETRYABLE_CLOUD_EMPTY"
            exposure.last_reconciliation_error = localOriginalMissing ? "Local original is missing; retry may require developer attention." : nil
        case .synced:
            exposure.sync_state = .failed
            exposure.last_reconciliation_rule = "LOCAL_SYNCED_CLOUD_EMPTY"
            exposure.last_reconciliation_error = "Local exposure is marked synced, but cloud exposure is empty."
            exposure.last_error = "Local exposure is marked synced, but cloud exposure is empty."
        case .empty:
            exposure.last_reconciliation_rule = local == nil ? "CLOUD_EMPTY_CREATED_LOCAL_MIRROR" : "EMPTY_CONSISTENT"
            exposure.last_reconciliation_error = nil
        }

        return exposure
    }

    private func shouldInspectUnmatchedLocal(_ exposure: LocalExposure, currentUserID: UUID) -> Bool {
        guard let ownerUserID = exposure.owner_user_id else {
            return true
        }

        return ownerUserID == currentUserID
    }

    private func normalizedPath(_ path: String?) -> String? {
        guard let path else {
            return nil
        }

        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isLocalOriginalMissing(_ exposure: LocalExposure) -> Bool {
        guard let localOriginalPath = exposure.local_original_path else {
            return false
        }

        return !photoStorageService.fileExists(at: localOriginalPath)
    }
}
