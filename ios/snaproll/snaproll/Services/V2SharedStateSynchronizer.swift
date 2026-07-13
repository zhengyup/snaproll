import Combine
import Foundation

struct V2SharedStatePollingConfiguration: Sendable, Equatable {
    let waitingForParticipantsInterval: TimeInterval
    let shootingInterval: TimeInterval
    let readyToRevealInterval: TimeInterval

    static let appDefault = V2SharedStatePollingConfiguration(
        waitingForParticipantsInterval: AppConfig.V2.waitingForParticipantsPollingInterval,
        shootingInterval: AppConfig.V2.sharedShootingPollingInterval,
        readyToRevealInterval: AppConfig.V2.readyToRevealPollingInterval
    )

    func interval(for status: V2Domain.RollStatus?) -> TimeInterval? {
        guard let status else {
            return nil
        }

        switch status {
        case .waitingForParticipants:
            return waitingForParticipantsInterval
        case .shooting:
            return shootingInterval
        case .readyToReveal:
            return readyToRevealInterval
        case .draft, .revealed:
            return nil
        }
    }
}

struct V2SharedStateSynchronizerSnapshot: Equatable {
    var isPollingConfigured = false
    var isPollingActive = false
    var isPollingBlocked = false
    var currentIntervalSeconds: TimeInterval?
    var lastRefreshAt: Date?
    var pollCount = 0
    var latestBackendState: V2Domain.RollStatus?
    var lastRefreshDurationMilliseconds: Double?
    var lastErrorMessage: String?
}

protocol SharedStateSynchronizing: AnyObject {
    @MainActor var snapshot: V2SharedStateSynchronizerSnapshot { get }
    @MainActor func seedLatestKnownState(_ status: V2Domain.RollStatus?)
    @MainActor func start() async
    @MainActor func stop() async
    @MainActor func handleSceneActivity(isActive: Bool) async
    @MainActor func refreshNow() async
}

actor V2SharedStateSynchronizerRegistry {
    static let shared = V2SharedStateSynchronizerRegistry()

    private var activeOwners: [UUID: UUID] = [:]

    func acquire(rollID: UUID, ownerID: UUID) -> Bool {
        if let currentOwner = activeOwners[rollID], currentOwner != ownerID {
            return false
        }

        activeOwners[rollID] = ownerID
        return true
    }

    func release(rollID: UUID, ownerID: UUID) {
        guard activeOwners[rollID] == ownerID else {
            return
        }

        activeOwners.removeValue(forKey: rollID)
    }
}

@MainActor
final class V2SharedStateSynchronizer: ObservableObject, SharedStateSynchronizing {
    typealias RefreshHandler = @Sendable () async throws -> V2Domain.RollStatus?
    typealias SleepHandler = @Sendable (TimeInterval) async -> Void

    @Published private(set) var snapshot = V2SharedStateSynchronizerSnapshot()

    private let rollID: UUID
    private let ownerID = UUID()
    private let configuration: V2SharedStatePollingConfiguration
    private let refreshHandler: RefreshHandler
    private let sleepHandler: SleepHandler
    private let registry: V2SharedStateSynchronizerRegistry
    private var pollingTask: Task<Void, Never>?
    private var ownsPollingLease = false

    init(
        rollID: UUID,
        configuration: V2SharedStatePollingConfiguration? = nil,
        registry: V2SharedStateSynchronizerRegistry = .shared,
        sleepHandler: @escaping SleepHandler = { seconds in
            let duration = max(seconds, 0)
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        refreshHandler: @escaping RefreshHandler
    ) {
        self.rollID = rollID
        self.configuration = configuration ?? .appDefault
        self.registry = registry
        self.sleepHandler = sleepHandler
        self.refreshHandler = refreshHandler
    }

    deinit {
        pollingTask?.cancel()
        let rollID = rollID
        let ownerID = ownerID
        let registry = registry
        Task {
            await registry.release(rollID: rollID, ownerID: ownerID)
        }
    }

    func start() async {
        snapshot.isPollingConfigured = true
        await performRefresh(incrementPollCount: false)
        await beginPollingLoopIfNeeded()
    }

    func seedLatestKnownState(_ status: V2Domain.RollStatus?) {
        snapshot.latestBackendState = status
        snapshot.currentIntervalSeconds = configuration.interval(for: status)
    }

    func stop() async {
        let activeTask = pollingTask
        pollingTask = nil
        activeTask?.cancel()
        await activeTask?.value

        if ownsPollingLease {
            await registry.release(rollID: rollID, ownerID: ownerID)
            ownsPollingLease = false
        }

        snapshot.isPollingActive = false
        snapshot.isPollingBlocked = false
        snapshot.currentIntervalSeconds = nil
    }

    func handleSceneActivity(isActive: Bool) async {
        if isActive {
            await start()
        } else {
            await stop()
        }
    }

    func refreshNow() async {
        await performRefresh(incrementPollCount: false)
        await beginPollingLoopIfNeeded()
    }

    private func beginPollingLoopIfNeeded() async {
        guard pollingTask == nil else {
            return
        }

        guard let interval = configuration.interval(for: snapshot.latestBackendState) else {
            snapshot.isPollingActive = false
            snapshot.currentIntervalSeconds = nil

            if ownsPollingLease {
                await registry.release(rollID: rollID, ownerID: ownerID)
                ownsPollingLease = false
            }
            return
        }

        let acquired = await registry.acquire(rollID: rollID, ownerID: ownerID)
        ownsPollingLease = acquired
        snapshot.isPollingBlocked = !acquired

        guard acquired else {
            snapshot.isPollingActive = false
            snapshot.currentIntervalSeconds = interval
            return
        }

        snapshot.isPollingActive = true
        snapshot.currentIntervalSeconds = interval

        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    private func runPollingLoop() async {
        while !Task.isCancelled {
            guard let interval = snapshot.currentIntervalSeconds else {
                break
            }

            await sleepHandler(interval)

            guard !Task.isCancelled else {
                break
            }

            await performRefresh(incrementPollCount: true)

            guard let nextInterval = configuration.interval(for: snapshot.latestBackendState) else {
                break
            }

            snapshot.currentIntervalSeconds = nextInterval
        }

        pollingTask = nil
        snapshot.isPollingActive = false

        if ownsPollingLease {
            await registry.release(rollID: rollID, ownerID: ownerID)
            ownsPollingLease = false
        }

        if configuration.interval(for: snapshot.latestBackendState) == nil {
            snapshot.currentIntervalSeconds = nil
            snapshot.isPollingBlocked = false
        }
    }

    private func performRefresh(incrementPollCount: Bool) async {
        let startedAt = CFAbsoluteTimeGetCurrent()

        do {
            let status = try await refreshHandler()
            snapshot.latestBackendState = status
            snapshot.lastRefreshAt = Date.now
            snapshot.lastRefreshDurationMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            snapshot.lastErrorMessage = nil

            if incrementPollCount {
                snapshot.pollCount += 1
            }
        } catch {
            snapshot.lastRefreshAt = Date.now
            snapshot.lastRefreshDurationMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            snapshot.lastErrorMessage = error.localizedDescription

            if incrementPollCount {
                snapshot.pollCount += 1
            }
        }
    }
}
