import Foundation
import BrowserSessionsCore

struct TestHarness {
    var failures = 0

    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition() {
            failures += 1
            fputs("FAIL \(file):\(line) — \(message)\n", stderr)
        }
    }

    mutating func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if actual != expected {
            failures += 1
            fputs("FAIL \(file):\(line) — \(message) expected \(expected), got \(actual)\n", stderr)
        }
    }
}

@MainActor
private func runDetectionSnapshotTests(_ harness: inout TestHarness) {
    harness.expectEqual(DetectionSnapshot(totalCount: 0).menuBarBadge, nil, "zero badge")
    harness.expectEqual(DetectionSnapshot(totalCount: 3).menuBarBadge, "3", "count badge")
    harness.expectEqual(DetectionSnapshot(totalCount: 101).menuBarBadge, "99+", "overflow badge")
    harness.expect(DetectionSnapshot(totalCount: 0).shouldShowMenuBarItem == false, "hide at zero")
    harness.expect(DetectionSnapshot(totalCount: 1).shouldShowMenuBarItem, "show when nonzero")
}

@MainActor
private func runVisibilityPolicyTests(_ harness: inout TestHarness) {
    let hide = MenuBarVisibilityPolicy.hideWhenEmpty
    harness.expect(hide.isInserted(for: .empty) == false, "hide policy empty")
    harness.expect(hide.isInserted(for: DetectionSnapshot(totalCount: 2)), "hide policy nonzero")
    let neutral = MenuBarVisibilityPolicy.neutralZeroStateWhenEmpty
    harness.expect(neutral.isInserted(for: .empty), "neutral always inserted empty")
    harness.expect(neutral.isInserted(for: DetectionSnapshot(totalCount: 2)), "neutral always inserted nonzero")
}

@MainActor
private func runSessionMonitorTests(_ harness: inout TestHarness) async {
    let monitor = SessionMonitor(snapshotProvider: { DetectionSnapshot(totalCount: 0) }, autostart: false)
    let before = monitor.snapshot.lastUpdated
    try? await Task.sleep(for: .milliseconds(10))
    await monitor.pollOnce()
    harness.expect(monitor.snapshot.lastUpdated >= before, "poll updates timestamp")
    let policy = MenuBarVisibilityPolicy.hideWhenEmpty
    var snapshot = DetectionSnapshot(totalCount: 1)
    harness.expect(policy.isInserted(for: snapshot), "transition start")
    snapshot = DetectionSnapshot(totalCount: 0)
    harness.expect(policy.isInserted(for: snapshot) == false, "transition to zero")

    let slowMonitor = SessionMonitor(snapshotProvider: {
        try? await Task.sleep(for: .milliseconds(50))
        return DetectionSnapshot(totalCount: 1)
    }, autostart: false)
    let pollTask = Task { await slowMonitor.pollOnce() }
    try? await Task.sleep(for: .milliseconds(10))
    harness.expect(slowMonitor.isRefreshing, "refresh flag true while poll is in flight")
    await pollTask.value
    harness.expect(slowMonitor.isRefreshing == false, "refresh flag clears after poll")

    final class PollCounter: @unchecked Sendable {
        var count = 0
    }
    final class MonitorBox: @unchecked Sendable {
        var monitor: SessionMonitor?
    }
    let counter = PollCounter()
    let monitorBox = MonitorBox()
    let queuedMonitor = SessionMonitor(snapshotProvider: {
        counter.count += 1
        if counter.count == 1 {
            Task { await monitorBox.monitor?.pollOnce() }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return DetectionSnapshot(totalCount: counter.count)
    }, autostart: false)
    monitorBox.monitor = queuedMonitor
    await queuedMonitor.pollOnce()
    harness.expectEqual(counter.count, 2, "refresh requested during active poll is queued")
    harness.expectEqual(queuedMonitor.snapshot.totalCount, 2, "queued refresh publishes latest snapshot")

    await testPollingStopsWhenMonitorIsReleased(&harness)
}

@MainActor
private func testPollingStopsWhenMonitorIsReleased(_ harness: inout TestHarness) async {
    final class Polls: @unchecked Sendable {
        var count = 0
    }
    let polls = Polls()
    var monitor: SessionMonitor? = SessionMonitor(pollInterval: .milliseconds(10), snapshotProvider: {
        polls.count += 1
        return .empty
    })
    try? await Task.sleep(for: .milliseconds(50))
    weak let released = monitor
    monitor = nil
    try? await Task.sleep(for: .milliseconds(30))
    let pollsAfterRelease = polls.count
    try? await Task.sleep(for: .milliseconds(60))
    harness.expect(pollsAfterRelease > 0, "monitor polled while alive")
    harness.expect(released == nil, "polling task does not keep the monitor alive")
    harness.expectEqual(polls.count, pollsAfterRelease, "polling stops once the monitor is gone")
}

@MainActor
enum BrowserSessionsTestRunnerApp {
    static func run() async {
        var harness = TestHarness()
        runDetectionSnapshotTests(&harness)
        runVisibilityPolicyTests(&harness)
        await runSessionMonitorTests(&harness)
        await runCommandRunnerTests(&harness)
        await runProcessTableTests(&harness)
        await runAgentBrowserClientTests(&harness)
        await runAgentBrowserProcessResolverTests(&harness)
        await runAutomationSignalClassifierTests(&harness)
        await runProcessIdentityTests(&harness)
        runURLSanitizerTests(&harness)
        await runProcessScannerTests(&harness)
        await runDetectionEngineTests(&harness)
        await runCloseCoordinatorTests(&harness)
        await runDegradationBannerTests(&harness)
        if harness.failures == 0 {
            print("BrowserSessionsTestRunner: all tests passed")
        } else {
            fputs("BrowserSessionsTestRunner: \(harness.failures) failure(s)\n", stderr)
            exit(1)
        }
    }
}

@main
enum BrowserSessionsTestRunnerMain {
    static func main() async {
        await BrowserSessionsTestRunnerApp.run()
    }
}
