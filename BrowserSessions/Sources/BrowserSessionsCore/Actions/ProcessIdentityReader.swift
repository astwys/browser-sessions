import Foundation

public protocol ProcessIdentityReading: Sendable {
    func currentIdentity(pid: Int32) -> ProcessIdentity?
}

public struct ProcessIdentityReader: ProcessIdentityReading, Sendable {
    private let lookup: @Sendable (Int32) -> ProcessRecord?

    public init(lookup: @escaping @Sendable (Int32) -> ProcessRecord? = ProcessTable.record(pid:)) {
        self.lookup = lookup
    }

    public func currentIdentity(pid: Int32) -> ProcessIdentity? {
        guard let record = lookup(pid) else { return nil }
        let parent = record.parentPID.flatMap(lookup)
        let classification = AutomationSignalClassifier.classify(
            executablePath: record.executablePath,
            commandLine: record.commandLine,
            parentCommandLine: parent?.commandLine
        )
        return ProcessIdentity(
            pid: record.pid,
            parentPID: record.parentPID,
            startTime: record.startTime,
            executablePath: record.executablePath,
            commandLine: record.commandLine,
            signalTokens: classification?.signalTokens ?? []
        )
    }
}
