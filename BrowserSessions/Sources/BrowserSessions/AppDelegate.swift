import AppKit
import BrowserSessionsCore
import os

enum MenuBarDiagnostics {
    private static let logger = Logger(subsystem: "com.browser-sessions.app", category: "MenuBar")

    static func logLaunch(policy: MenuBarVisibilityPolicy, snapshot: DetectionSnapshot, inserted: Bool) {
        let message = "launch policy=\(String(describing: policy)) count=\(snapshot.totalCount) inserted=\(inserted)"
        logger.info("\(message, privacy: .public)")
        if ProcessInfo.processInfo.environment["BROWSER_SESSIONS_DEBUG"] == "1" {
            fputs("[BrowserSessions] \(message)\n", stderr)
        }
    }

    static func logVisibilityChange(count: Int, inserted: Bool) {
        let message = "visibility count=\(count) inserted=\(inserted)"
        logger.info("\(message, privacy: .public)")
        if ProcessInfo.processInfo.environment["BROWSER_SESSIONS_DEBUG"] == "1" {
            fputs("[BrowserSessions] \(message)\n", stderr)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
