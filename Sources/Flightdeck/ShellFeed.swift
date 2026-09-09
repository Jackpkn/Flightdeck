import Foundation

/// Low-level Darwin file watcher for `~/.zsh_history` / `~/.bash_history`.
/// Monitors developer terminal activity using `DispatchSourceFileSystemObject` on a background
/// utility queue and streams shell commands into Flightdeck's live activity feed.
@Observable
public final class ShellFeed {
    public static let shared = ShellFeed()

    public struct ShellCommand: Sendable, Equatable {
        public let timestamp: Date
        public let command: String
    }

    private var fileDescriptor: Int32 = -1
    private var dispatchSource: (any DispatchSourceFileSystemObject)?
    private var fileOffset: UInt64 = 0
    private let queue = DispatchQueue(label: "com.flightdeck.shellfeed", qos: .utility)
    private var onCommandReceived: (@Sendable @MainActor (ShellCommand) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    /// Locate the active shell history file (`~/.zsh_history` prioritized, fallback to `~/.bash_history`).
    public static var historyURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let zsh = home.appendingPathComponent(".zsh_history")
        if FileManager.default.fileExists(atPath: zsh.path) {
            return zsh
        }
        let bash = home.appendingPathComponent(".bash_history")
        if FileManager.default.fileExists(atPath: bash.path) {
            return bash
        }
        return nil
    }

    /// Start watching the shell history file and streaming commands.
    public func start(onCommand: @escaping @Sendable @MainActor (ShellCommand) -> Void) {
        self.onCommandReceived = onCommand
        guard let url = Self.historyURL else { return }

        queue.async { [weak self] in
            guard let self else { return }
            self.loadInitialHistory(url: url)
            self.watchFile(url: url)
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.dispatchSource?.cancel()
            self.dispatchSource = nil
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
    }

    // MARK: - Initial Tail Load

    private func loadInitialHistory(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        // Read the last ~16KB of history to seed the recent feed without loading megabytes of archive
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let readLength: UInt64 = min(fileSize, 16 * 1024)
        let startOffset = fileSize > readLength ? fileSize - readLength : 0

        _ = try? handle.seek(toOffset: startOffset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else {
            fileOffset = fileSize
            return
        }
        fileOffset = fileSize

        let content = String(decoding: data, as: UTF8.self)
        let lines = content.components(separatedBy: .newlines)
        var parsed: [ShellCommand] = []

        for line in lines {
            if let cmd = Self.parseHistoryLine(line) {
                parsed.append(cmd)
            }
        }

        // Send the last 30 commands
        let recent = Array(parsed.suffix(30))
        DispatchQueue.main.async { [weak self] in
            for item in recent {
                self?.onCommandReceived?(item)
            }
        }
    }

    // MARK: - Darwin DispatchSource Watching

    private func watchFile(url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let data = source.data
            if data.contains(.delete) || data.contains(.rename) {
                // History file was rotated or truncated by zsh session exit; re-bind
                self.rebind(url: url)
            } else if data.contains(.write) || data.contains(.extend) {
                self.readNewHistory(url: url)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        self.dispatchSource = source
        source.resume()
    }

    private func rebind(url: URL) {
        dispatchSource?.cancel()
        dispatchSource = nil
        fileOffset = 0
        // Small delay to let disk flush the new file
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.loadInitialHistory(url: url)
            self?.watchFile(url: url)
        }
    }

    private func readNewHistory(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        if fileSize < fileOffset {
            // File was truncated
            fileOffset = 0
        }

        _ = try? handle.seek(toOffset: fileOffset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        fileOffset += UInt64(data.count)

        let content = String(decoding: data, as: UTF8.self)
        let lines = content.components(separatedBy: .newlines)

        var newCommands: [ShellCommand] = []
        for line in lines {
            if let cmd = Self.parseHistoryLine(line) {
                newCommands.append(cmd)
            }
        }

        guard !newCommands.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            for item in newCommands {
                self?.onCommandReceived?(item)
            }
        }
    }

    // MARK: - Line Parsing

    /// Parses a single line from `.zsh_history` or `.bash_history`.
    /// Handles both extended zsh format (`: 1788952602:0;git status`) and plain text commands.
    public static func parseHistoryLine(_ line: String) -> ShellCommand? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix(": ") {
            // Extended format: ": <unix_time>:<duration>;<command>"
            let rest = trimmed.dropFirst(2)
            if let semiIndex = rest.firstIndex(of: ";") {
                let meta = rest[..<semiIndex]
                let cmdString = String(rest[rest.index(after: semiIndex)...]).trimmingCharacters(in: .whitespaces)
                guard !cmdString.isEmpty else { return nil }

                // Parse unix timestamp
                let tsString = meta.split(separator: ":").first
                let epoch = tsString.flatMap { Double($0) }
                let date = epoch.map { Date(timeIntervalSince1970: $0) } ?? Date()

                return ShellCommand(timestamp: date, command: cmdString)
            }
        }

        // Plain command line fallback
        return ShellCommand(timestamp: Date(), command: trimmed)
    }
}
