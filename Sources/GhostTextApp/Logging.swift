import Foundation

/// File-backed logger.
///
/// Live runtime verification is expensive, so the app is built to be debugged by
/// reading logs rather than by watching it. Anything worth knowing about buffer
/// state, caret geometry, or inference latency goes here.
public final class FileLog: @unchecked Sendable {
    public static let app = FileLog(name: "ghost-text")
    public static let probe = FileLog(name: "ax-probe")

    private let handle: FileHandle?
    private let lock = NSLock()
    private let formatter: DateFormatter

    public let url: URL

    init(name: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GhostText", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        url = dir.appendingPathComponent("\(name).log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()

        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
    }

    public func callAsFunction(_ message: @autoclosure () -> String) {
        write(message())
    }

    public func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        handle?.write(Data(line.utf8))
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    /// Starts a fresh section so one probe run is distinguishable from the next.
    public func banner(_ title: String) {
        write("")
        write("=== \(title) ===")
    }
}
