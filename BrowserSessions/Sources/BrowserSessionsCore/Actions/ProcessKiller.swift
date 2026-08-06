import Darwin
import Foundation

public enum ProcessKillResult: Equatable, Sendable {
    case success
    case failed(String)
}

public protocol ProcessKilling: Sendable {
    func terminate(pid: Int32) -> ProcessKillResult
}

public struct ProcessKiller: ProcessKilling, Sendable {
    public init() {}

    public func terminate(pid: Int32) -> ProcessKillResult {
        guard pid > 0 else { return .failed("invalid PID") }
        if kill(pid, SIGTERM) == 0 {
            return .success
        }
        return .failed(String(cString: strerror(errno)))
    }
}
