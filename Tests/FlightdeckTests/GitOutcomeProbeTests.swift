import Testing
import Foundation
@testable import Flightdeck

/// These build a real throwaway git repository rather than mocking `git`, because the
/// thing under test is precisely whether the command invocations are right.
@Suite("Git outcome probe", .serialized)
struct GitOutcomeProbeTests {

    private func makeRepo() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fd-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        run("git", ["init", "-q", "-b", "main"], in: dir)
        run("git", ["config", "user.email", "test@example.com"], in: dir)
        run("git", ["config", "user.name", "Test"], in: dir)
        run("git", ["config", "commit.gpgsign", "false"], in: dir)
        return dir
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String], in dir: URL) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [tool] + args
        p.currentDirectoryURL = dir
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func write(_ text: String, to name: String, in dir: URL) throws {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    @Test("A directory that isn't a repository reports no outcome")
    func nonRepository() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fd-plain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(GitOutcomeProbe.probe(cwd: dir.path, files: [], since: nil, until: nil) == nil)
    }

    @Test("A committed file is reported as surviving in HEAD")
    func committedFileSurvives() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        try write("let a = 1\n", to: "Sources/Kept.swift", in: repo)
        run("git", ["add", "."], in: repo)
        run("git", ["commit", "-qm", "keep"], in: repo)

        let outcome = try #require(GitOutcomeProbe.probe(
            cwd: repo.path,
            files: [repo.appendingPathComponent("Sources/Kept.swift").path],
            since: nil, until: nil
        ))
        #expect(outcome.filesInHead == 1)
        #expect(outcome.filesDropped == 0)
        #expect(outcome.survivalRate == 1.0)
    }

    @Test("A file deleted after being written is reported as dropped")
    func deletedFileIsDropped() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        try write("scratch\n", to: "Throwaway.swift", in: repo)
        try write("keep\n", to: "Kept.swift", in: repo)
        run("git", ["add", "."], in: repo)
        run("git", ["commit", "-qm", "both"], in: repo)
        run("git", ["rm", "-q", "Throwaway.swift"], in: repo)
        run("git", ["commit", "-qm", "drop"], in: repo)

        let outcome = try #require(GitOutcomeProbe.probe(
            cwd: repo.path,
            files: [
                repo.appendingPathComponent("Throwaway.swift").path,
                repo.appendingPathComponent("Kept.swift").path,
            ],
            since: nil, until: nil
        ))
        #expect(outcome.filesInHead == 1)
        #expect(outcome.filesDropped == 1)
        #expect(abs(outcome.survivalRate - 0.5) < 0.001)
    }

    @Test("A file written but never committed is reported as uncommitted, not dropped")
    func uncommittedFileIsTracked() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        try write("seed\n", to: "Seed.swift", in: repo)
        run("git", ["add", "."], in: repo)
        run("git", ["commit", "-qm", "seed"], in: repo)
        try write("wip\n", to: "WorkInProgress.swift", in: repo)

        let outcome = try #require(GitOutcomeProbe.probe(
            cwd: repo.path,
            files: [repo.appendingPathComponent("WorkInProgress.swift").path],
            since: nil, until: nil
        ))
        #expect(outcome.filesInHead == 0)
        #expect(outcome.filesUncommitted == 1)
        #expect(outcome.filesDropped == 0)
    }

    @Test("Commits and committed line counts inside the window are measured")
    func countsCommitsInWindow() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let start = Date().addingTimeInterval(-3600)
        try write("a\nb\nc\n", to: "Three.swift", in: repo)
        run("git", ["add", "."], in: repo)
        run("git", ["commit", "-qm", "three lines"], in: repo)

        let outcome = try #require(GitOutcomeProbe.probe(
            cwd: repo.path,
            files: [repo.appendingPathComponent("Three.swift").path],
            since: start, until: Date().addingTimeInterval(60)
        ))
        #expect(outcome.commits == 1)
        #expect(outcome.linesAdded == 3)
        #expect(outcome.netLines == 3)
    }

    @Test("Commits outside the window are excluded")
    func excludesCommitsOutsideWindow() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        try write("x\n", to: "Old.swift", in: repo)
        run("git", ["add", "."], in: repo)
        run("git", ["commit", "-qm", "old"], in: repo)

        // A window entirely in the future contains nothing.
        let outcome = try #require(GitOutcomeProbe.probe(
            cwd: repo.path,
            files: [repo.appendingPathComponent("Old.swift").path],
            since: Date().addingTimeInterval(3600),
            until: Date().addingTimeInterval(7200)
        ))
        #expect(outcome.commits == 0)
        #expect(outcome.linesAdded == 0)
    }

    @Test("An empty repository with no commits is handled")
    func emptyRepository() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let outcome = try #require(GitOutcomeProbe.probe(cwd: repo.path, files: [], since: nil, until: nil))
        // No window was given, so no commit claim is made rather than a bogus zero.
        #expect(outcome.commits == nil)
        #expect(outcome.filesInHead == 0)
    }

    @Test("Files outside the repository are ignored rather than counted as dropped")
    func ignoresFilesOutsideRepo() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        try write("x\n", to: "In.swift", in: repo)
        run("git", ["add", "."], in: repo)
        run("git", ["commit", "-qm", "in"], in: repo)

        let outcome = try #require(GitOutcomeProbe.probe(
            cwd: repo.path,
            files: [
                repo.appendingPathComponent("In.swift").path,
                "/tmp/somewhere/else/Outside.swift",
            ],
            since: nil, until: nil
        ))
        #expect(outcome.filesConsidered == 1)
        #expect(outcome.filesInHead == 1)
        #expect(outcome.filesDropped == 0)
    }

    @Test("Survival rate is zero-safe when no files were considered")
    func survivalRateWithNoFiles() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let outcome = try #require(GitOutcomeProbe.probe(cwd: repo.path, files: [], since: nil, until: nil))
        #expect(outcome.filesConsidered == 0)
        #expect(outcome.survivalRate == 0)
    }
}

@Suite("Commit window safety", .serialized)
struct CommitWindowTests {

    /// Without `--since`, `git log --numstat` walks the whole history: measured at
    /// 47,296 lines and 6.2s on a real monorepo, for a figure that says nothing about
    /// the session. No window means no claim.
    @Test("An unknown window yields no commit statistics at all")
    func noWindowNoClaim() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fd-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for args in [["init", "-q", "-b", "main"],
                     ["config", "user.email", "t@e.com"],
                     ["config", "user.name", "T"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["git"] + args
            p.currentDirectoryURL = dir
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }
        try Data("x\n".utf8).write(to: dir.appendingPathComponent("f.txt"))
        for args in [["add", "."], ["commit", "-qm", "c"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["git"] + args
            p.currentDirectoryURL = dir
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }

        let outcome = try #require(GitOutcomeProbe.probe(cwd: dir.path, files: [], since: nil, until: nil))
        #expect(outcome.commits == nil)
        #expect(outcome.linesAdded == nil)
        #expect(outcome.netLines == nil)
    }

    @Test("A probe of a large real repository stays well inside the timeout")
    func staysFast() throws {
        // Only meaningful on a machine that has a sizeable repo handy; skipped otherwise.
        let candidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/Flightdeck").path
        guard FileManager.default.fileExists(atPath: candidate) else { return }

        let started = Date()
        _ = GitOutcomeProbe.probe(
            cwd: candidate, files: [],
            since: Date().addingTimeInterval(-30 * 86_400), until: Date()
        )
        #expect(Date().timeIntervalSince(started) < GitOutcomeProbe.timeout)
    }
}

@Suite("Commit attribution", .serialized)
struct CommitAttributionTests {

    private func makeRepo() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fd-attr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"],
                     ["config", "user.email", "t@e.com"],
                     ["config", "user.name", "T"],
                     ["config", "commit.gpgsign", "false"]] {
            git(args, dir)
        }
        return dir
    }

    private func git(_ args: [String], _ dir: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git"] + args
        p.currentDirectoryURL = dir
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    /// The bug this guards: counting every commit made during the session window
    /// attributed a developer's own hand-written commits to Claude. On real data that
    /// turned one session into "309 commits".
    @Test("Commits that don't touch the session's files are not attributed to it")
    func excludesUnrelatedCommits() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let since = Date().addingTimeInterval(-3600)

        // What the session wrote.
        try Data("a\nb\n".utf8).write(to: repo.appendingPathComponent("Session.swift"))
        git(["add", "."], repo)
        git(["commit", "-qm", "session work"], repo)

        // Three unrelated commits by the developer in the same window.
        for i in 1...3 {
            try Data("x\n".utf8).write(to: repo.appendingPathComponent("Manual\(i).swift"))
            git(["add", "."], repo)
            git(["commit", "-qm", "manual \(i)"], repo)
        }

        let outcome = try #require(GitOutcomeProbe.probe(
            cwd: repo.path,
            files: [repo.appendingPathComponent("Session.swift").path],
            since: since, until: Date().addingTimeInterval(60)
        ))
        #expect(outcome.commits == 1)
        #expect(outcome.linesAdded == 2)
    }

    @Test("A session with no tracked files makes no commit claim")
    func noFilesNoClaim() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try Data("x\n".utf8).write(to: repo.appendingPathComponent("A.swift"))
        git(["add", "."], repo)
        git(["commit", "-qm", "c"], repo)

        let outcome = try #require(GitOutcomeProbe.probe(
            cwd: repo.path, files: [], since: Date().addingTimeInterval(-3600), until: Date()
        ))
        #expect(outcome.commits == nil)
    }

    @Test("Later edits to a session's file still count as its commits")
    func countsFollowUpCommits() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let since = Date().addingTimeInterval(-3600)
        let file = repo.appendingPathComponent("Tracked.swift")

        try Data("one\n".utf8).write(to: file)
        git(["add", "."], repo)
        git(["commit", "-qm", "first"], repo)
        try Data("one\ntwo\n".utf8).write(to: file)
        git(["add", "."], repo)
        git(["commit", "-qm", "second"], repo)

        let outcome = try #require(GitOutcomeProbe.probe(
            cwd: repo.path, files: [file.path], since: since, until: Date().addingTimeInterval(60)
        ))
        #expect(outcome.commits == 2)
    }
}
