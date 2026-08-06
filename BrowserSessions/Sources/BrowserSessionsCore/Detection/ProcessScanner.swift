import Foundation

public protocol ProcessSnapshotProviding: Sendable {
    func records() async -> [ProcessRecord]
}

public struct ProcessSnapshotProvider: ProcessSnapshotProviding, Sendable {
    private let commandRunner: any CommandRunning

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func records() async -> [ProcessRecord] {
        let result = await commandRunner.run(
            executable: "ps",
            arguments: ["-axo", "pid=,ppid=,lstart=,command=", "-ww"],
            timeout: .seconds(2)
        )
        guard result.succeeded else { return [] }
        return ProcessArguments.parsePSOutput(result.stdout)
    }
}

public protocol ProcessScanning: Sendable {
    func scan() async -> [DetectedEntry]
    func scan(records: [ProcessRecord]) -> [DetectedEntry]
}

public struct ProcessScanner: ProcessScanning, Sendable {
    private let processSnapshotProvider: any ProcessSnapshotProviding

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.processSnapshotProvider = ProcessSnapshotProvider(commandRunner: commandRunner)
    }

    public init(processSnapshotProvider: any ProcessSnapshotProviding) {
        self.processSnapshotProvider = processSnapshotProvider
    }

    public func scan() async -> [DetectedEntry] {
        await scan(records: processSnapshotProvider.records())
    }

    public func scan(records: [ProcessRecord]) -> [DetectedEntry] {
        Self.entries(from: records)
    }

    public static func entries(from records: [ProcessRecord]) -> [DetectedEntry] {
        let commandLinesByPID = Dictionary(uniqueKeysWithValues: records.map { ($0.pid, $0.commandLine) })
        return records.compactMap { record in
            let parentCommandLine = record.parentPID.flatMap { commandLinesByPID[$0] }
            guard let classification = AutomationSignalClassifier.classify(
                executablePath: record.executablePath,
                commandLine: record.commandLine,
                parentCommandLine: parentCommandLine
            ) else { return nil }
            let identity = ProcessIdentity(
                pid: record.pid,
                parentPID: record.parentPID,
                startTime: record.startTime,
                executablePath: record.executablePath,
                commandLine: record.commandLine,
                signalTokens: classification.signalTokens
            )
            return DetectedEntry.process(
                identity: identity,
                confidence: classification.tier,
                displayName: classification.displayName,
                commandLineSnippet: URLSanitizer.sanitizedCommandLineSnippet(record.commandLine),
                parentProcessSummary: parentCommandLine.map { URLSanitizer.sanitizedCommandLineSnippet($0, maxLength: 80) },
                signalReason: classification.signalTokens.joined(separator: ", ")
            )
        }
    }
}
