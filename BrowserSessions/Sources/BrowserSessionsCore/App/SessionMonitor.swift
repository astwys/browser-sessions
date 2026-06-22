import Foundation
import Observation

@Observable
@MainActor
public final class SessionMonitor {
    public private(set) var snapshot: DetectionSnapshot = .empty
    private var timerTask: Task<Void, Never>?
    private let pollInterval: Duration
    private let snapshotProvider: @Sendable () async -> DetectionSnapshot

    public init(
        pollInterval: Duration = .seconds(3),
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
        {
            let env = ProcessInfo.processInfo.environment["BROWSER_SESSIONS_STUB_COUNT"]
            let count = env.flatMap(Int.init) ?? 0
            return DetectionSnapshot(totalCount: count, lastUpdated: Date())
        }
    }

    public func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            await self?.pollOnce()
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(3))
                await self?.pollOnce()
            }
        }
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    public func pollOnce() async {
        snapshot = await snapshotProvider()
    }

    public func applySnapshot(_ snapshot: DetectionSnapshot) {
        self.snapshot = snapshot
    }
}
