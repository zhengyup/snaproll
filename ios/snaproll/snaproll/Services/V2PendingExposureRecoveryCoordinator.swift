import Foundation
import OSLog

@MainActor
final class V2PendingExposureRecoveryCoordinator: PendingExposureRecovering {
    private enum RecoveryStage: String {
        case none = "NONE"
        case upload = "UPLOAD"
        case metadata = "METADATA"
    }

    private struct RecoveryContext {
        let roll: LocalRoll
        let participantID: UUID?
    }

    private let authRepository: any AuthRepository
    private let rollRepository: any RollRepository
    private let participantRepository: any ParticipantRepository
    private let exposureMirrorStore: any ExposureMirrorStore
    private let syncRunner: any ExposureSyncRunning
    private let reconciler: (any ExposureReconciling)?
    private let logger: Logger
    private var activeRecoveryRollIDs: Set<UUID> = []

    init(
        authRepository: any AuthRepository,
        rollRepository: any RollRepository,
        participantRepository: any ParticipantRepository,
        exposureMirrorStore: any ExposureMirrorStore,
        syncRunner: any ExposureSyncRunning,
        reconciler: (any ExposureReconciling)? = nil,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pzy.snaproll",
            category: "V2PendingRecovery"
        )
    ) {
        self.authRepository = authRepository
        self.rollRepository = rollRepository
        self.participantRepository = participantRepository
        self.exposureMirrorStore = exposureMirrorStore
        self.syncRunner = syncRunner
        self.reconciler = reconciler
        self.logger = logger
    }

    func recoverPendingWorkForCurrentSession() async {
        do {
            guard let session = try await authRepository.currentSession() else {
                return
            }

            let rolls = try await rollRepository.fetchRolls()
            for roll in rolls {
                guard let context = try await makeRecoveryContext(for: roll, currentUserID: session.userID) else {
                    continue
                }

                await recoverPendingWork(using: context)
            }
        } catch {
            logger.error("Global pending-work recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recoverPendingWork(forRollID rollID: UUID) async {
        do {
            guard let session = try await authRepository.currentSession(),
                  let roll = try await rollRepository.fetchRoll(id: rollID),
                  let context = try await makeRecoveryContext(for: roll, currentUserID: session.userID) else {
                return
            }

            await recoverPendingWork(using: context)
        } catch {
            logger.error(
                "Roll-scoped pending-work recovery failed for \(rollID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func recoverPendingWork(using context: RecoveryContext) async {
        let rollID = context.roll.id
        guard !activeRecoveryRollIDs.contains(rollID) else {
            logger.debug("Recovery already active for roll \(rollID.uuidString, privacy: .public)")
            return
        }

        activeRecoveryRollIDs.insert(rollID)
        defer { activeRecoveryRollIDs.remove(rollID) }

        do {
            await reconciler?.reconcileRoll(id: rollID)

            let allExposures = try await exposureMirrorStore.fetchExposures(forRollID: rollID)
            let scopedExposures = allExposures
                .filter { exposure in
                    guard let participantID = context.participantID else {
                        return true
                    }

                    return exposure.participant_id == participantID
                }
                .sorted { $0.exposure_number < $1.exposure_number }

            guard !scopedExposures.isEmpty else {
                return
            }

            let normalizedExposures = try await normalize(scopedExposures, for: context.roll)
            let hasPendingWork = normalizedExposures.contains { shouldResume($0) }

            guard hasPendingWork else {
                return
            }

            let summary = try await syncRunner.processPendingExposures(
                forRollID: rollID,
                participantID: context.participantID
            )
            logger.debug(
                "Recovered roll \(rollID.uuidString, privacy: .public): processed \(summary.processedCount, privacy: .public), synced \(summary.syncedCount, privacy: .public), failed \(summary.failedCount, privacy: .public)"
            )
        } catch {
            logger.error(
                "Recovery run failed for roll \(rollID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            try? await markRecoveryFailure(forRollID: rollID, participantID: context.participantID, error: error)
        }
    }

    private func makeRecoveryContext(
        for roll: LocalRoll,
        currentUserID: UUID
    ) async throws -> RecoveryContext? {
        if roll.type == .shared {
            let participants = try await participantRepository.fetchParticipants(forRollID: roll.id)
            guard let participant = participants.first(where: { $0.user_id == currentUserID }) else {
                return nil
            }

            return RecoveryContext(roll: roll, participantID: participant.id)
        }

        return RecoveryContext(roll: roll, participantID: nil)
    }

    private func normalize(_ exposures: [LocalExposure], for roll: LocalRoll) async throws -> [LocalExposure] {
        let recoveredAt = Date.now

        for exposure in exposures {
            let originalState = exposure.sync_state
            let normalizedState = normalizedState(for: exposure)
            let recoveryReason = recoveryReason(for: exposure, normalizedState: normalizedState)

            if normalizedState != originalState {
                exposure.sync_state = normalizedState
            }

            guard originalState != .empty && originalState != .synced else {
                continue
            }

            exposure.last_recovery_from_state = originalState.rawValue
            exposure.last_recovery_to_state = normalizedState.rawValue
            exposure.last_recovery_reason = recoveryReason
            exposure.last_recovery_error = nil
            exposure.last_recovered_at = recoveredAt
            exposure.updated_at = recoveredAt
            try await exposureMirrorStore.saveExposure(exposure)

            logger.debug(
                "Normalized exposure \(exposure.id.uuidString, privacy: .public) in roll \(roll.id.uuidString, privacy: .public) from \(originalState.rawValue, privacy: .public) to \(normalizedState.rawValue, privacy: .public)"
            )
        }

        return exposures
    }

    private func normalizedState(for exposure: LocalExposure) -> V2Domain.ExposureSyncState {
        switch exposure.sync_state {
        case .empty, .synced, .localOnly, .metadataPending:
            return exposure.sync_state
        case .uploading:
            return .localOnly
        case .failed:
            return derivedRecoveryStage(for: exposure) == .metadata ? .metadataPending : .localOnly
        }
    }

    private func recoveryReason(for exposure: LocalExposure, normalizedState: V2Domain.ExposureSyncState) -> String {
        switch exposure.sync_state {
        case .localOnly:
            return "Recovered pending local capture; upload will resume."
        case .uploading:
            return "Recovered stale uploading state after restart; upload will restart."
        case .metadataPending:
            return "Recovered completed upload; metadata completion will resume without re-uploading."
        case .failed:
            switch derivedRecoveryStage(for: exposure) {
            case .metadata:
                return "Recovered failed metadata completion using preserved cloud storage path."
            case .upload:
                return "Recovered failed upload stage; upload will retry."
            case .none:
                return "Recovered failed exposure for retry."
            }
        case .empty:
            return "No recovery needed for empty exposure."
        case .synced:
            return "No recovery needed for synced exposure."
        }
    }

    private func derivedRecoveryStage(for exposure: LocalExposure) -> RecoveryStage {
        hasCloudStoragePath(exposure) ? .metadata : .upload
    }

    private func shouldResume(_ exposure: LocalExposure) -> Bool {
        switch exposure.sync_state {
        case .localOnly, .metadataPending, .uploading, .failed:
            return true
        case .empty, .synced:
            return false
        }
    }

    private func hasCloudStoragePath(_ exposure: LocalExposure) -> Bool {
        guard let cloudStoragePath = exposure.cloud_storage_path else {
            return false
        }

        return !cloudStoragePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func markRecoveryFailure(
        forRollID rollID: UUID,
        participantID: UUID?,
        error: Error
    ) async throws {
        let recoveredAt = Date.now
        let exposures = try await exposureMirrorStore.fetchExposures(forRollID: rollID)
            .filter { exposure in
                guard let participantID else {
                    return true
                }

                return exposure.participant_id == participantID
            }

        for exposure in exposures where shouldResume(exposure) {
            exposure.last_recovery_error = error.localizedDescription
            exposure.last_recovered_at = recoveredAt
            exposure.updated_at = recoveredAt
            try await exposureMirrorStore.saveExposure(exposure)
        }
    }
}
