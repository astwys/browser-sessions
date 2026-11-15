import Foundation

public struct ProcessIdentity: Equatable, Sendable, Codable {
    public let pid: Int32
    public let parentPID: Int32?
    public let startTime: Date
    public let executablePath: String
    public let executableBasename: String
    public let commandLine: String
    public let signalTokens: [String]

    public init(
        pid: Int32,
        parentPID: Int32? = nil,
        startTime: Date,
        executablePath: String,
        executableBasename: String? = nil,
        commandLine: String,
        signalTokens: [String]
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.startTime = startTime
        self.executablePath = executablePath
        self.executableBasename = executableBasename ?? URL(fileURLWithPath: executablePath).lastPathComponent
        self.commandLine = commandLine
        self.signalTokens = signalTokens
    }

    /// Start times come from the kernel with microsecond precision, so they must match exactly:
    /// a reused PID always has a different start time.
    public func matches(current: ProcessIdentity) -> Bool {
        guard pid == current.pid else { return false }
        guard startTime == current.startTime else { return false }
        guard executablePath == current.executablePath else { return false }
        guard commandLine == current.commandLine else { return false }
        if signalTokens.isEmpty && current.signalTokens.isEmpty { return true }
        let currentSignals = Set(current.signalTokens.map { $0.lowercased() })
        return signalTokens.contains { currentSignals.contains($0.lowercased()) }
    }
}
