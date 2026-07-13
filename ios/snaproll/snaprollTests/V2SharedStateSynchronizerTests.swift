import Foundation
import Testing
@testable import snaproll

@MainActor
struct V2SharedStateSynchronizerTests {
    @Test
    func pollingStartsCorrectly() async throws {
        let sleeper = ControlledSharedStateSleepHandler()
        let refresher = SequencedSharedStateRefresher(results: [.success(.waitingForParticipants)])
        let synchronizer = V2SharedStateSynchronizer(
            rollID: UUID(),
            configuration: .testDefault,
            registry: V2SharedStateSynchronizerRegistry(),
            sleepHandler: { interval in
                await sleeper.sleep(for: interval)
            },
            refreshHandler: {
                try await refresher.refresh()
            }
        )
        synchronizer.seedLatestKnownState(.waitingForParticipants)

        await synchronizer.start()

        #expect(synchronizer.snapshot.isPollingConfigured)
        #expect(synchronizer.snapshot.isPollingActive)
        #expect(synchronizer.snapshot.isPollingBlocked == false)
        #expect(synchronizer.snapshot.latestBackendState == .waitingForParticipants)
        #expect(synchronizer.snapshot.currentIntervalSeconds == 5)

        await synchronizer.stop()
    }

    @Test
    func pollingIntervalChangesWithRollState() async throws {
        let sleeper = ControlledSharedStateSleepHandler()
        let refresher = SequencedSharedStateRefresher(
            results: [.success(.waitingForParticipants), .success(.shooting)]
        )
        let synchronizer = V2SharedStateSynchronizer(
            rollID: UUID(),
            configuration: .testDefault,
            registry: V2SharedStateSynchronizerRegistry(),
            sleepHandler: { interval in
                await sleeper.sleep(for: interval)
            },
            refreshHandler: {
                try await refresher.refresh()
            }
        )
        synchronizer.seedLatestKnownState(.waitingForParticipants)

        await synchronizer.start()
        #expect(synchronizer.snapshot.currentIntervalSeconds == 5)

        await sleeper.resumeNext()
        await waitUntil {
            synchronizer.snapshot.pollCount == 1
        }

        #expect(synchronizer.snapshot.latestBackendState == .shooting)
        #expect(synchronizer.snapshot.currentIntervalSeconds == 10)
        #expect(synchronizer.snapshot.pollCount == 1)

        await synchronizer.stop()
    }

    @Test
    func screenDisappearanceStopsPolling() async throws {
        let sleeper = ControlledSharedStateSleepHandler()
        let refresher = SequencedSharedStateRefresher(results: [.success(.waitingForParticipants)])
        let synchronizer = V2SharedStateSynchronizer(
            rollID: UUID(),
            configuration: .testDefault,
            registry: V2SharedStateSynchronizerRegistry(),
            sleepHandler: { interval in
                await sleeper.sleep(for: interval)
            },
            refreshHandler: {
                try await refresher.refresh()
            }
        )
        synchronizer.seedLatestKnownState(.waitingForParticipants)

        await synchronizer.start()
        await synchronizer.stop()

        #expect(synchronizer.snapshot.isPollingActive == false)
        #expect(synchronizer.snapshot.currentIntervalSeconds == nil)
    }

    @Test
    func foregroundResumesPolling() async throws {
        let sleeper = ControlledSharedStateSleepHandler()
        let refresher = SequencedSharedStateRefresher(
            results: [.success(.waitingForParticipants), .success(.waitingForParticipants)]
        )
        let synchronizer = V2SharedStateSynchronizer(
            rollID: UUID(),
            configuration: .testDefault,
            registry: V2SharedStateSynchronizerRegistry(),
            sleepHandler: { interval in
                await sleeper.sleep(for: interval)
            },
            refreshHandler: {
                try await refresher.refresh()
            }
        )
        synchronizer.seedLatestKnownState(.waitingForParticipants)

        await synchronizer.handleSceneActivity(isActive: true)
        await synchronizer.handleSceneActivity(isActive: false)
        await synchronizer.handleSceneActivity(isActive: true)

        #expect(synchronizer.snapshot.isPollingActive)
        #expect(await refresher.callCount == 2)

        await synchronizer.stop()
    }

    @Test
    func pollingFailuresRecoverAutomatically() async throws {
        let sleeper = ControlledSharedStateSleepHandler()
        let refresher = SequencedSharedStateRefresher(
            results: [
                .success(.waitingForParticipants),
                .failure(V2RepositoryError.network("Offline")),
                .success(.waitingForParticipants)
            ]
        )
        let synchronizer = V2SharedStateSynchronizer(
            rollID: UUID(),
            configuration: .testDefault,
            registry: V2SharedStateSynchronizerRegistry(),
            sleepHandler: { interval in
                await sleeper.sleep(for: interval)
            },
            refreshHandler: {
                try await refresher.refresh()
            }
        )
        synchronizer.seedLatestKnownState(.waitingForParticipants)

        await synchronizer.start()

        await sleeper.resumeNext()
        await waitUntil {
            synchronizer.snapshot.pollCount == 1
        }

        #expect(synchronizer.snapshot.lastErrorMessage == "Offline")
        #expect(synchronizer.snapshot.isPollingActive)

        await sleeper.resumeNext()
        await waitUntil {
            synchronizer.snapshot.pollCount == 2
        }

        #expect(synchronizer.snapshot.lastErrorMessage == nil)
        #expect(synchronizer.snapshot.pollCount == 2)

        await synchronizer.stop()
    }

    @Test
    func repeatedPollsDoNotDuplicateStateAndOnlyOneSynchronizerExistsPerRoll() async throws {
        let rollID = UUID()
        let sleeper = ControlledSharedStateSleepHandler()
        let refresher = SequencedSharedStateRefresher(results: [.success(.waitingForParticipants)])
        let registry = V2SharedStateSynchronizerRegistry()
        let firstSynchronizer = V2SharedStateSynchronizer(
            rollID: rollID,
            configuration: .testDefault,
            registry: registry,
            sleepHandler: { interval in
                await sleeper.sleep(for: interval)
            },
            refreshHandler: {
                try await refresher.refresh()
            }
        )
        let secondSynchronizer = V2SharedStateSynchronizer(
            rollID: rollID,
            configuration: .testDefault,
            registry: registry,
            sleepHandler: { _ in },
            refreshHandler: {
                .waitingForParticipants
            }
        )
        firstSynchronizer.seedLatestKnownState(.waitingForParticipants)
        secondSynchronizer.seedLatestKnownState(.waitingForParticipants)

        await firstSynchronizer.start()
        await secondSynchronizer.start()

        #expect(firstSynchronizer.snapshot.isPollingActive)
        #expect(secondSynchronizer.snapshot.isPollingActive == false)
        #expect(secondSynchronizer.snapshot.isPollingBlocked)

        await firstSynchronizer.stop()
        await secondSynchronizer.stop()
    }

    @Test
    func revealedRollStopsPolling() async throws {
        let sleeper = ControlledSharedStateSleepHandler()
        let refresher = SequencedSharedStateRefresher(results: [.success(.revealed)])
        let synchronizer = V2SharedStateSynchronizer(
            rollID: UUID(),
            configuration: .testDefault,
            registry: V2SharedStateSynchronizerRegistry(),
            sleepHandler: { interval in
                await sleeper.sleep(for: interval)
            },
            refreshHandler: {
                try await refresher.refresh()
            }
        )

        await synchronizer.start()

        #expect(synchronizer.snapshot.latestBackendState == .revealed)
        #expect(synchronizer.snapshot.isPollingActive == false)
        #expect(synchronizer.snapshot.currentIntervalSeconds == nil)
    }
}

private extension V2SharedStatePollingConfiguration {
    static let testDefault = V2SharedStatePollingConfiguration(
        waitingForParticipantsInterval: 5,
        shootingInterval: 10,
        readyToRevealInterval: 5
    )
}

private actor ControlledSharedStateSleepHandler {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(for _: TimeInterval) async {
        if Task.isCancelled {
            return
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        } onCancel: {
            Task {
                await self.resumeAll()
            }
        }
    }

    func resumeNext() {
        guard !continuations.isEmpty else {
            return
        }

        let continuation = continuations.removeFirst()
        continuation.resume()
    }

    func resumeAll() {
        let activeContinuations = continuations
        continuations.removeAll()
        activeContinuations.forEach { $0.resume() }
    }
}

private actor SequencedSharedStateRefresher {
    private var results: [Result<V2Domain.RollStatus?, Error>]
    private(set) var callCount = 0

    init(results: [Result<V2Domain.RollStatus?, Error>]) {
        self.results = results
    }

    func refresh() throws -> V2Domain.RollStatus? {
        callCount += 1

        guard !results.isEmpty else {
            return .waitingForParticipants
        }

        return try results.removeFirst().get()
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while !condition() && DispatchTime.now().uptimeNanoseconds < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
