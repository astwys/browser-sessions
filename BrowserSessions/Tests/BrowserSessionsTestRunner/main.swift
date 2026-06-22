import Foundation
import BrowserSessionsCore

private struct TestHarness {
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
    harness.expectEqual(MenuBarPresentation.from(snapshot: .empty, hideSupported: true), .hidden, "hidden presentation")
    harness.expectEqual(MenuBarPresentation.from(snapshot: .empty, hideSupported: false), .neutralZeroState, "neutral zero state")
    harness.expectEqual(MenuBarPresentation.from(snapshot: DetectionSnapshot(totalCount: 3), hideSupported: true), .badge("3"), "badge presentation")
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
    monitor.applySnapshot(DetectionSnapshot(totalCount: 5))
    harness.expectEqual(monitor.snapshot.totalCount, 5, "apply snapshot count")
    harness.expectEqual(monitor.snapshot.menuBarBadge, "5", "apply snapshot badge")
    let policy = MenuBarVisibilityPolicy.hideWhenEmpty
    var snapshot = DetectionSnapshot(totalCount: 1)
    harness.expect(policy.isInserted(for: snapshot), "transition start")
    snapshot = DetectionSnapshot(totalCount: 0)
    harness.expect(policy.isInserted(for: snapshot) == false, "transition to zero")
}

@MainActor
enum BrowserSessionsTestRunnerApp {
    static func run() async {
        var harness = TestHarness()
        runDetectionSnapshotTests(&harness)
        runVisibilityPolicyTests(&harness)
        await runSessionMonitorTests(&harness)
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
