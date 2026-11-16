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
    }
}

/// Reads the per-poll state (`lastUpdated`) in its own view, so the scene body and the menu bar label
/// depend on `snapshot` only and redraw only when detection results change.
private struct PopoverContent: View {
    let monitor: SessionMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        PopoverShellView(
            snapshot: monitor.snapshot,
            lastUpdated: monitor.lastUpdated,
            onCloseCompleted: {
                await monitor.pollOnce()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            // The first size, when the popover opens, is set as is; later ones follow the content.
            withAnimation(contentHeight == 0 ? nil : .popover) { contentHeight = height }
        }
        .fitsWindowHeight(contentHeight)
        // Reduce Motion: every change in the popover lands at once, window included.
        .transaction { if reduceMotion { $0.animation = nil } }
    }
}
