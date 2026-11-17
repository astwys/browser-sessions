import Darwin
import Foundation
import os

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

/// Runs a command found on an augmented PATH. Returns within `timeout` plus fixed grace periods,
/// whatever the command or its children do.
public struct CommandRunner: CommandRunning, Sendable {
    /// Time a command gets to exit after SIGTERM before it and its children get SIGKILL.
    private static let terminationGrace: Duration = .milliseconds(500)
    /// Time to keep reading output after the command exits. A background child it spawned may hold
    /// the pipes open indefinitely, so the runner never waits for EOF.
    private static let drainGrace: Duration = .milliseconds(250)

    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        timeout: Duration = .seconds(2)
    ) async -> CommandResult {
        let process = Process()
        let stdout = PipeCollector()
        let stderr = PipeCollector()
        let exited = Latch()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.environment = Self.environmentWithAugmentedPath()
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe
        process.terminationHandler = { _ in exited.open() }

        do {
            try process.run()
        } catch {
            stdout.stop()
            stderr.stop()
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }

        var timedOut = false
        if await exited.wait(timeout: timeout) == false {
            timedOut = true
            // Read before the first signal: once the command dies, its children move to launchd.
            let descendants = Self.descendants(of: process.processIdentifier)
            Self.signal(process, descendants, SIGTERM)
            let exitedInGrace = await exited.wait(timeout: Self.terminationGrace)
            Self.signal(process, descendants, SIGKILL)
            if exitedInGrace == false { await exited.wait() }
        }

        async let stdoutDrained = stdout.eof.wait(timeout: Self.drainGrace)
        async let stderrDrained = stderr.eof.wait(timeout: Self.drainGrace)
        _ = await (stdoutDrained, stderrDrained)
        stdout.stop()
        stderr.stop()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout.string,
            stderr: timedOut ? "command timed out" : stderr.string,
            timedOut: timedOut
        )
    }

    /// Every process the command started. Children forked after this read, during the grace period, are missed.
    private static func descendants(of root: Int32) -> [ProcessRecord] {
        let children = Dictionary(grouping: ProcessTable.all(), by: { $0.parentPID ?? -1 })
        var tree = children[root, default: []]
        var index = 0
        while index < tree.count {
            tree += children[tree[index].pid, default: []]
            index += 1
        }
        return tree
    }

    /// Signals the command, and each descendant that is still the same process: same PID and start time.
    /// The command is signalled through `Process`, which also works when its process table entry can't be read.
    private static func signal(_ process: Process, _ descendants: [ProcessRecord], _ signal: Int32) {
        if process.isRunning {
            kill(process.processIdentifier, signal)
        }
        for record in descendants where ProcessTable.record(pid: record.pid)?.startTime == record.startTime {
            kill(record.pid, signal)
        }
    }

    private static func environmentWithAugmentedPath() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let inherited = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        // The inherited PATH wins, so the app runs the same agent-browser as the user's shell; the usual
        // install places are a fallback for a Finder launch, whose PATH has none of them.
        let components = inherited.split(separator: ":").map(String.init) + commonExecutableDirectories()
        environment["PATH"] = Array(NSOrderedSet(array: components))
            .compactMap { $0 as? String }
            .joined(separator: ":")
        return environment
    }

    /// Finder-launched apps get a minimal PATH, so add the usual places a Node CLI is installed.
    private static func commonExecutableDirectories() -> [String] {
        var directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            NSHomeDirectory() + "/.local/bin"
        ]
        let fnmRoot = NSHomeDirectory() + "/.local/share/fnm/node-versions"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: fnmRoot) {
            directories += versions
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                .map { fnmRoot + "/" + $0 + "/installation/bin" }
        }
        return directories
    }
}

/// Collects a pipe's output through `readabilityHandler` only. The handler runs serially per file
/// handle, so chunks are appended in order; nothing else reads from the pipe.
private final class PipeCollector: @unchecked Sendable {
    let pipe = Pipe()
    let eof = Latch()
    private let data = OSAllocatedUnfairLock(initialState: Data())

    init() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.eof.open()
            } else {
                self.data.withLock { $0.append(chunk) }
            }
        }
    }

    var string: String {
        data.withLock { String(decoding: $0, as: UTF8.self) }
    }

    /// Stops reading. The read end closes when the pipe is deallocated; closing it here could race
    /// with a handler call that is already in flight.
    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
    }
}

/// A one-way gate that async callers can wait on, optionally with a timeout.
final class Latch: Sendable {
    private struct State: Sendable {
        var isOpen = false
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func open() {
        let waiters = state.withLock { state in
            state.isOpen = true
            defer { state.waiters.removeAll() }
            return Array(state.waiters.values)
        }
        waiters.forEach { $0.resume() }
    }

    /// Returns when the latch opens or the calling task is cancelled.
    func wait() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { state in
                    if state.isOpen || Task.isCancelled { return true }
                    state.waiters[id] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.waiters.removeValue(forKey: id) }?.resume()
        }
    }

    /// Returns true if the latch opened before `timeout` elapsed.
    func wait(timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.wait(); return true }
            group.addTask { try? await Task.sleep(for: timeout); return false }
            _ = await group.next()
            group.cancelAll()
            return state.withLock { $0.isOpen }
        }
    }
}
