import AppKit
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
        // The `MenuBarExtra(_:systemImage:)` initializer draws only the image; a Label draws the count too.
        MenuBarExtra(isInserted: $isMenuBarInserted) {
            PopoverContent(monitor: monitor)
        } label: {
            Label(monitor.snapshot.menuBarBadge ?? "", systemImage: "globe")
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Browser Sessions, \(monitor.snapshot.totalCount) running")
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
            PermissionsOnboardingView()
        }
    }
}

/// Reads the per-poll state (`lastUpdated`, `isRefreshing`) in its own view, so the scene body and the
/// menu bar label depend on `snapshot` only and redraw only when detection results change.
private struct PopoverContent: View {
    let monitor: SessionMonitor
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        PopoverShellView(
            snapshot: monitor.snapshot,
            lastUpdated: monitor.lastUpdated,
            isRefreshing: monitor.isRefreshing,
            onCloseCompleted: {
                await monitor.pollOnce()
            },
            onRefresh: {
                await monitor.pollOnce()
            },
            onOpenSettings: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .background(WindowHeightFitter(contentHeight: contentHeight))
    }
}
