import Darwin
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

/// Reads the live process table through libproc and sysctl instead of spawning `ps`: no PATH lookup,
/// no locale-dependent date parsing, and start times with microsecond precision.
/// Only the current user's processes are returned; the app can neither read the arguments of nor
/// signal anyone else's.
public enum ProcessTable {
    public static func all() -> [ProcessRecord] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        // Headroom for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        var buffer = argumentBuffer()
        return pids.prefix(Int(count)).compactMap { record(pid: $0, buffer: &buffer) }
    }

    public static func record(pid: Int32) -> ProcessRecord? {
        var buffer = argumentBuffer()
        return record(pid: pid, buffer: &buffer)
    }

    private static func record(pid: Int32, buffer: inout [UInt8]) -> ProcessRecord? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize,
              info.pbi_uid == getuid(),
              let executablePath = executablePath(pid: pid),
              let commandLine = commandLine(pid: pid, buffer: &buffer)
        else { return nil }
        let startTime = TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        return ProcessRecord(
            pid: pid,
            parentPID: info.pbi_ppid == 0 ? nil : Int32(info.pbi_ppid),
            startTime: Date(timeIntervalSince1970: startTime),
            executablePath: executablePath,
            commandLine: commandLine
        )
    }

    private static func executablePath(pid: Int32) -> String? {
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        guard length > 0 else { return nil }
        return String(decoding: path.prefix(Int(length)), as: UTF8.self)
    }

    private static func commandLine(pid: Int32, buffer: inout [UInt8]) -> String? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        return buffer.prefix(size).withUnsafeBytes { arguments(procArgs: $0) }.joined(separator: " ")
    }

    /// argv from a KERN_PROCARGS2 buffer: argc, the exec path, NUL padding, argv, then the environment.
    /// The environment is never read: it routinely holds secrets. argc alone doesn't guarantee that. A
    /// process that rewrites its title (Node's `process.title`) writes over the space its other arguments
    /// used, so reading argc strings runs on into the environment. Reading stops at the first `NAME=value`
    /// string after argv[0], the shape of every environment entry.
    public static func arguments(procArgs raw: UnsafeRawBufferPointer) -> [String] {
        guard raw.count > MemoryLayout<Int32>.size else { return [] }
        let argc = Int(raw.loadUnaligned(as: Int32.self))
        let size = raw.count
        var index = MemoryLayout<Int32>.size
        while index < size, raw[index] != 0 { index += 1 }
        while index < size, raw[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, raw[index] != 0 { index += 1 }
            let argument = String(decoding: raw[start..<index], as: UTF8.self)
            // ponytail: also drops a genuine NAME=value argument and the ones after it, which only shortens
            // the command shown; detection keys on --flags and paths.
            if arguments.isEmpty == false, isEnvironmentEntry(argument) { break }
            arguments.append(argument)
            index += 1
        }
        return arguments
    }

    private static func isEnvironmentEntry(_ string: String) -> Bool {
        guard let equals = string.firstIndex(of: "="), equals != string.startIndex else { return false }
        let name = string[..<equals]
        return name.first.map { $0 == "_" || $0.isLetter } == true && name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    private static func argumentBuffer() -> [UInt8] {
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib = [CTL_KERN, KERN_ARGMAX]
        if sysctl(&mib, 2, &argmax, &size, nil, 0) != 0 || argmax <= 0 {
            argmax = 1 << 20
        }
        return [UInt8](repeating: 0, count: Int(argmax))
    }
}
