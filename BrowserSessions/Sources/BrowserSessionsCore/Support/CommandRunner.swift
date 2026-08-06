import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    public var succeeded: Bool {
        exitCode == 0 && !timedOut
    }
}

public protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: Duration) async -> CommandResult
}

public struct CommandRunner: CommandRunning, Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        timeout: Duration = .seconds(2)
    ) async -> CommandResult {
        await Task.detached {
            Self.runSync(executable: executable, arguments: arguments, timeout: timeout)
        }.value
    }

    private static func runSync(
        executable: String,
        arguments: [String],
        timeout: Duration
    ) -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = PipeCaptureBuffer()
        let stderrBuffer = PipeCaptureBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }
        defer {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.environment = environmentWithAugmentedPath()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return CommandResult(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false
            )
        }

        let deadline = Date().addingTimeInterval(timeout.timeInterval)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return CommandResult(
                exitCode: process.terminationStatus,
                stdout: stdoutBuffer.string,
                stderr: "command timed out",
                timedOut: true
            )
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdoutBuffer.string,
            stderr: stderrBuffer.string,
            timedOut: false
        )
    }

    private static func environmentWithAugmentedPath() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let inherited = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let additions = commonExecutableDirectories()
        let components = (additions + inherited.split(separator: ":").map(String.init))
        environment["PATH"] = Array(NSOrderedSet(array: components))
            .compactMap { $0 as? String }
            .joined(separator: ":")
        return environment
    }

    private static func commonExecutableDirectories() -> [String] {
        var directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            NSHomeDirectory() + "/.local/bin"
        ]
        let fnmRoot = NSHomeDirectory() + "/.local/share/fnm/node-versions"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: fnmRoot) {
            directories += versions.map { fnmRoot + "/" + $0 + "/installation/bin" }
        }
        return directories
    }
}

private final class PipeCaptureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func append(_ chunk: Data) {
        guard chunk.isEmpty == false else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
