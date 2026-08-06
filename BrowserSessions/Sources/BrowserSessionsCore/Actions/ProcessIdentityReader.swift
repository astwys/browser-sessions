import Foundation

public protocol ProcessIdentityReading: Sendable {
    func currentIdentity(pid: Int32) async -> ProcessIdentity?
}

public struct ProcessIdentityReader: ProcessIdentityReading, Sendable {
    private let commandRunner: any CommandRunning

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func currentIdentity(pid: Int32) async -> ProcessIdentity? {
        let result = await commandRunner.run(
            executable: "ps",
            arguments: ["-p", String(pid), "-o", "pid=,ppid=,lstart=,command=", "-ww"],
            timeout: .seconds(2)
        )
        guard result.succeeded else { return nil }
        guard let record = ProcessArguments.parsePSOutput(result.stdout).first(where: { $0.pid == pid }) else { return nil }
        let parentCommandLine = await parentCommandLine(for: record.parentPID)
        let classification = AutomationSignalClassifier.classify(
            executablePath: record.executablePath,
            commandLine: record.commandLine,
            parentCommandLine: parentCommandLine
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

    private func parentCommandLine(for parentPID: Int32?) async -> String? {
        guard let parentPID, parentPID > 0 else { return nil }
        let result = await commandRunner.run(
            executable: "ps",
            arguments: ["-p", String(parentPID), "-o", "command=", "-ww"],
            timeout: .seconds(2)
        )
        guard result.succeeded else { return nil }
        let command = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }
}
