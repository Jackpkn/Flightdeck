import Foundation

/// What actually became of the code a session wrote.
///
/// This is the question no cloud usage dashboard can answer: it needs the repository
/// on disk, not just the transcript. "Claude wrote 9,371 lines" is a claim about
/// activity; "6,200 of them are still in HEAD" is a claim about value.
struct GitOutcome: Equatable, Sendable {
    /// Files from the session that live inside this repository.
    let filesConsidered: Int
    /// Still present in HEAD — the work stuck.
    let filesInHead: Int
    /// Written but never committed — still in the working tree.
    let filesUncommitted: Int
    /// Gone from both HEAD and the working tree — the work was thrown away.
    let filesDropped: Int
    /// Commits in the session's window that touched files this session wrote — nil
    /// when the window is unknown.
    ///
    /// Deliberately not "commits during the window": that counts everything anyone
    /// did in the repository at the time, including hand-written commits and merges,
    /// and attributing those to the session would badly overstate its output.
    let commits: Int?
    /// Lines added by those commits, per `git log --numstat`. Nil with the window.
    let linesAdded: Int?
    let linesRemoved: Int?

    /// Share of the session's files that survived into HEAD.
    var survivalRate: Double {
        guard filesConsidered > 0 else { return 0 }
        return Double(filesInHead) / Double(filesConsidered)
    }

    var netLines: Int? {
        guard let linesAdded, let linesRemoved else { return nil }
        return linesAdded - linesRemoved
    }
}

/// Runs `git` against a session's working directory to measure what survived.
enum GitOutcomeProbe {

    /// Guards against a pathological repo hanging the scan.
    static let timeout: TimeInterval = 10
    /// Upper bound on commits examined, so a huge history can never stall the UI.
    static let maxCommits = 500
    /// Cap on pathspec arguments, well inside ARG_MAX for any real session.
    static let maxPathspecs = 200

    /// Returns nil when `cwd` isn't inside a git repository — the honest answer,
    /// rather than a zeroed result that reads like "nothing survived".
    static func probe(cwd: String, files: Set<String>, since: Date?, until: Date?) -> GitOutcome? {
        guard !cwd.isEmpty, FileManager.default.fileExists(atPath: cwd) else { return nil }
        guard let root = repositoryRoot(at: cwd) else { return nil }

        let tracked = filesInHead(root: root)
        // `git rev-parse` returns a fully resolved path while the session's recorded
        // paths may still contain symlinks (/var vs /private/var on macOS), so both
        // sides are canonicalised before any prefix comparison.
        let canonicalRoot = Self.canonical(root)
        let rootPrefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"

        var considered = 0
        var inHead = 0
        var uncommitted = 0
        var dropped = 0
        var repoRelativePaths: [String] = []

        for file in files {
            // Only files belonging to this repository can be judged by it.
            let canonicalFile = Self.canonical(file)
            guard canonicalFile.hasPrefix(rootPrefix) else { continue }
            considered += 1
            let relative = String(canonicalFile.dropFirst(rootPrefix.count))
            repoRelativePaths.append(relative)
            if tracked.contains(relative) {
                inHead += 1
            } else if FileManager.default.fileExists(atPath: file) {
                uncommitted += 1
            } else {
                dropped += 1
            }
        }

        let stats = commitStats(
            root: root, since: since, until: until, paths: repoRelativePaths
        )

        return GitOutcome(
            filesConsidered: considered,
            filesInHead: inHead,
            filesUncommitted: uncommitted,
            filesDropped: dropped,
            commits: stats?.commits,
            linesAdded: stats?.added,
            linesRemoved: stats?.removed
        )
    }

    /// Resolves symlinks in the directory portion of a path. The leaf is left alone so
    /// a deleted file still canonicalises correctly.
    private static func canonical(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let name = url.lastPathComponent
        return name.isEmpty ? parent.path : parent.appendingPathComponent(name).path
    }

    // MARK: - git calls

    private static func repositoryRoot(at path: String) -> String? {
        guard let out = git(["rev-parse", "--show-toplevel"], in: path) else { return nil }
        let root = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : root
    }

    /// Every path tracked in HEAD, read once — far cheaper than one `cat-file` per file.
    private static func filesInHead(root: String) -> Set<String> {
        guard let out = git(["ls-tree", "-r", "--name-only", "HEAD"], in: root) else { return [] }
        return Set(out.split(separator: "\n").map(String.init))
    }

    /// Nil when there is no known window to measure. Without `--since`, `git log`
    /// walks the entire history — on a real monorepo that is tens of thousands of
    /// lines and several seconds, for a number that would be meaningless anyway.
    private static func commitStats(
        root: String, since: Date?, until: Date?, paths: [String]
    ) -> (commits: Int, added: Int, removed: Int)? {
        // Without a window, or without any file to attribute against, there is no
        // honest number to report.
        guard let since, !paths.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        var args = [
            "log", "--numstat", "--pretty=format:%H",
            "--max-count=\(maxCommits)",
            "--since=\(iso.string(from: since))",
        ]
        if let until { args.append("--until=\(iso.string(from: until))") }
        // Pathspec keeps the count to commits that actually touched this session's
        // files, rather than everything that happened in the repo meanwhile.
        args.append("--")
        args.append(contentsOf: paths.prefix(maxPathspecs))

        guard let out = git(args, in: root) else { return nil }

        var commits = 0
        var added = 0
        var removed = 0
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if parts.count == 3 {
                // numstat marks binary files with "-", which has no line count.
                added += Int(parts[0]) ?? 0
                removed += Int(parts[1]) ?? 0
            } else if !line.isEmpty {
                commits += 1
            }
        }
        return (commits, added, removed)
    }

    /// Runs git with output captured. Returns nil on non-zero exit — including the
    /// "not a repository" and "no commits yet" cases, which callers handle as absence.
    private static func git(_ args: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        // Keep the user's global hooks and pagers out of a background measurement.
        var env = ProcessInfo.processInfo.environment
        env["GIT_PAGER"] = "cat"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        // A child that fills an undrained pipe blocks forever, so stderr is consumed
        // on its own thread even though its contents are discarded.
        let errorDrain = DispatchQueue(label: "com.flightdeck.git-stderr")
        errorDrain.async { _ = stderr.fileHandleForReading.readDataToEndOfFile() }

        // Kill the process if it outlives the budget; without this the read below
        // would wait on it indefinitely.
        let watchdog = DispatchWorkItem { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
