import Foundation

public struct DetectionSnapshot: Equatable, Sendable {
    public var entries: [DetectedEntry]
    public var degradedReason: String?
    public var lastUpdated: Date

    public static let empty = DetectionSnapshot(entries: [], lastUpdated: .distantPast)

    public init(totalCount: Int, lastUpdated: Date = Date()) {
        self.entries = (0..<max(0, totalCount)).map { index in
            DetectedEntry(
                id: "stub-\(index)",
                source: .agentBrowser,
                sessionName: "Stub \(index + 1)",
                displayName: "Stub \(index + 1)"
            )
        }
        self.degradedReason = nil
        self.lastUpdated = lastUpdated
    }

    public init(entries: [DetectedEntry], degradedReason: String? = nil, lastUpdated: Date = Date()) {
        self.entries = entries
        self.degradedReason = degradedReason
        self.lastUpdated = lastUpdated
    }

    public var totalCount: Int { entries.count }

    public var knownSessions: [DetectedEntry] {
        entries.filter { $0.source == .agentBrowser }
    }

    public var highConfidenceProcesses: [DetectedEntry] {
        entries.filter { $0.source == .process && $0.confidence == .high }
    }

    public var lowConfidenceProcesses: [DetectedEntry] {
        entries.filter { $0.source == .process && $0.confidence == .low }
    }

    public var menuBarBadge: String? {
        guard totalCount > 0 else { return nil }
        return totalCount > 99 ? "99+" : String(totalCount)
    }

    public var shouldShowMenuBarItem: Bool {
        totalCount > 0
    }
}

public enum MenuBarVisibilityPolicy: Equatable, Sendable {
    case hideWhenEmpty
    case neutralZeroStateWhenEmpty

    public static func fromEnvironment() -> MenuBarVisibilityPolicy {
        ProcessInfo.processInfo.environment["BROWSER_SESSIONS_FORCE_ZERO_STATE"] == "1"
            ? .neutralZeroStateWhenEmpty
            : .hideWhenEmpty
    }

    public func isInserted(for snapshot: DetectionSnapshot) -> Bool {
        switch self {
        case .hideWhenEmpty:
            return snapshot.shouldShowMenuBarItem
        case .neutralZeroStateWhenEmpty:
            return true
        }
    }
}
