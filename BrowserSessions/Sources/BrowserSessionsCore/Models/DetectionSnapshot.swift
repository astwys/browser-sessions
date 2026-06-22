import Foundation

public struct DetectionSnapshot: Equatable, Sendable {
    public var totalCount: Int
    public var lastUpdated: Date

    public static let empty = DetectionSnapshot(totalCount: 0, lastUpdated: .distantPast)

    public init(totalCount: Int, lastUpdated: Date = Date()) {
        self.totalCount = max(0, totalCount)
        self.lastUpdated = lastUpdated
    }

    public var menuBarBadge: String? {
        guard totalCount > 0 else { return nil }
        return totalCount > 99 ? "99+" : String(totalCount)
    }

    public var shouldShowMenuBarItem: Bool {
        totalCount > 0
    }

    public var isNeutralZeroState: Bool {
        totalCount == 0
    }
}

public enum MenuBarPresentation: Equatable, Sendable {
    case hidden
    case neutralZeroState
    case badge(String)

    public static func from(snapshot: DetectionSnapshot, hideSupported: Bool) -> MenuBarPresentation {
        if snapshot.totalCount > 0 {
            return .badge(snapshot.menuBarBadge ?? String(snapshot.totalCount))
        }
        return hideSupported ? .hidden : .neutralZeroState
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
