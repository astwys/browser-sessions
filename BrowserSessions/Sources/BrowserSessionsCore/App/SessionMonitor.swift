import Foundation
import Observation

@Observable
@MainActor
public final class SessionMonitor {
    public private(set) var snapshot: DetectionSnapshot = .empty
    public private(set) var isRefreshing = false
    private var refreshQueued = false
    private var timerTask: Task<Void, Never>?
    private let pollInterval: Duration
    private let snapshotProvider: @Sendable () async -> DetectionSnapshot

    public init(
        pollInterval: Duration = .seconds(5),
        snapshotProvider: @escaping @Sendable () async -> DetectionSnapshot = { .empty },
        autostart: Bool = true
    ) {
        self.pollInterval = pollInterval
        self.snapshotProvider = snapshotProvider
        self.snapshot = Self.initialSnapshotFromEnvironment()
        if autostart {
            start()
        }
    }

    /// Reads stub env synchronously so the menu bar can appear before the first async poll.
    public static func initialSnapshotFromEnvironment() -> DetectionSnapshot {
        let env = ProcessInfo.processInfo.environment["BROWSER_SESSIONS_STUB_COUNT"]
        let count = env.flatMap(Int.init) ?? 0
        return DetectionSnapshot(totalCount: count, lastUpdated: Date())
    }

    public static func defaultSnapshotProvider() -> @Sendable () async -> DetectionSnapshot {
        if ProcessInfo.processInfo.environment["BROWSER_SESSIONS_STUB_COUNT"] != nil {
            return {
                let env = ProcessInfo.processInfo.environment["BROWSER_SESSIONS_STUB_COUNT"]
                let count = env.flatMap(Int.init) ?? 0
                return DetectionSnapshot(totalCount: count, lastUpdated: Date())
            }
        }
        let engine = DetectionEngine()
        return {
            await engine.snapshot()
        }
    }

    public func start() {
        guard timerTask == nil else { return }
        let interval = pollInterval
        // Holds `self` weakly between polls and ends once the monitor is gone.
        timerTask = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                await self?.pollOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    public func pollOnce() async {
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshQueued = false
            snapshot = await snapshotProvider()
        } while refreshQueued && !Task.isCancelled
    }
}
