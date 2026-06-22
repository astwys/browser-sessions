import SwiftUI
import BrowserSessionsCore

@main
struct BrowserSessionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = SessionMonitor(snapshotProvider: SessionMonitor.defaultSnapshotProvider())
    @State private var isMenuBarInserted: Bool

    private let visibilityPolicy: MenuBarVisibilityPolicy

    init() {
        let policy = MenuBarVisibilityPolicy.fromEnvironment()
        let snapshot = SessionMonitor.initialSnapshotFromEnvironment()
        let inserted = policy.isInserted(for: snapshot)
        visibilityPolicy = policy
        _isMenuBarInserted = State(initialValue: inserted)
        MenuBarDiagnostics.logLaunch(policy: policy, snapshot: snapshot, inserted: inserted)
    }

    var body: some Scene {
        MenuBarExtra(
            menuBarTitle,
            systemImage: "globe",
            isInserted: $isMenuBarInserted
        ) {
            PopoverShellView(snapshot: monitor.snapshot)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: monitor.snapshot.totalCount) { _, count in
            let inserted = visibilityPolicy.isInserted(for: monitor.snapshot)
            if isMenuBarInserted != inserted {
                isMenuBarInserted = inserted
                MenuBarDiagnostics.logVisibilityChange(count: count, inserted: inserted)
            }
        }

        Settings {
            EmptyView()
        }
    }

    private var menuBarTitle: String {
        switch MenuBarPresentation.from(snapshot: monitor.snapshot, hideSupported: visibilityPolicy == .hideWhenEmpty) {
        case .badge(let text):
            return text
        case .neutralZeroState, .hidden:
            return ""
        }
    }
}
