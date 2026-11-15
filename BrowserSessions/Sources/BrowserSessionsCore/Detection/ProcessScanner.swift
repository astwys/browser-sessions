import Foundation

public enum ProcessScanner {
    public static func entries(from records: [ProcessRecord]) -> [DetectedEntry] {
        let commandLinesByPID = Dictionary(records.map { ($0.pid, $0.commandLine) }, uniquingKeysWith: { first, _ in first })
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
