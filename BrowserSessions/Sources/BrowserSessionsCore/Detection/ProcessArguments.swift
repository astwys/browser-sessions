import Foundation

public struct ProcessRecord: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32?
    public let startTime: Date
    public let executablePath: String
    public let commandLine: String

    public init(pid: Int32, parentPID: Int32?, startTime: Date, executablePath: String, commandLine: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.startTime = startTime
        self.executablePath = executablePath
        self.commandLine = commandLine
    }
}

public enum ProcessArguments {
    private static let lstartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()

    public static func parsePSOutput(_ stdout: String, now: Date = Date()) -> [ProcessRecord] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            parsePSLine(String(line), now: now)
        }
    }

    private static func parsePSLine(_ line: String, now: Date) -> ProcessRecord? {
        if line.contains("|") {
            return parseDelimitedPSLine(line, now: now)
        }
        return parseWhitespacePSLine(line)
    }

    private static func parseDelimitedPSLine(_ line: String, now: Date) -> ProcessRecord? {
        let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5,
              let pid = Int32(parts[0].trimmingCharacters(in: .whitespaces)),
              let ppid = Int32(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        let elapsedSeconds = TimeInterval(Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0)
        let executable = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let commandLine = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessRecord(pid: pid, parentPID: ppid, startTime: now.addingTimeInterval(-elapsedSeconds), executablePath: executable, commandLine: commandLine)
    }

    private static func parseWhitespacePSLine(_ line: String) -> ProcessRecord? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 8,
              let pid = Int32(parts[0]),
              let ppid = Int32(parts[1])
        else { return nil }
        let lstart = [parts[2], parts[3], parts[4], parts[5], parts[6]].joined(separator: " ")
        let commandLine = parts[7]
        let executable = inferExecutablePath(from: commandLine)
        return ProcessRecord(pid: pid, parentPID: ppid, startTime: lstartFormatter.date(from: lstart) ?? .distantPast, executablePath: executable, commandLine: commandLine)
    }

    private static func inferExecutablePath(from commandLine: String) -> String {
        for marker in [".app/Contents/MacOS/"] {
            if let range = commandLine.range(of: marker), let nextFlag = commandLine[range.upperBound...].range(of: " --") {
                return String(commandLine[..<nextFlag.lowerBound])
            }
        }
        return commandLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? commandLine
    }
}
