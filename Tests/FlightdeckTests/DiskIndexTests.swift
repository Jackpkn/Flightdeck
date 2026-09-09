import Foundation
import Testing
@testable import Flightdeck

/// The contract for the whole incremental scheme is one sentence: **after
/// applying changes, the index must hold exactly what a fresh full walk would
/// have found.** Every test here mutates a real temporary tree and asserts that
/// equality, because the failure mode of delta arithmetic isn't a crash — it's
/// numbers that are quietly wrong and drift further with every update.
struct DiskIndexTests {
    // MARK: - Fixture

    private func makeTree() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flightdeck-index-\(UUID().uuidString)")
        let fm = FileManager.default

        try fm.createDirectory(at: root.appendingPathComponent("photos"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("code/src"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)

        try write(root.appendingPathComponent("readme.md"), kb: 2)
        try write(root.appendingPathComponent("photos/a.jpg"), kb: 40)
        try write(root.appendingPathComponent("photos/b.jpg"), kb: 60)
        try write(root.appendingPathComponent("code/main.swift"), kb: 8)
        try write(root.appendingPathComponent("code/src/util.swift"), kb: 4)
        try write(root.appendingPathComponent("movie.mp4"), kb: 900)
        // The temp directory lives under /var, which is a symlink to
        // /private/var — hand back the canonical spelling so the test asks
        // about the same paths the index stores.
        return URL(fileURLWithPath: DiskIndex.canonical(root))
    }

    private func write(_ url: URL, kb: Int) throws {
        try Data(repeating: 0x41, count: kb * 1024).write(to: url)
    }

    /// What a cold walk of the same tree reports — the reference answer.
    private func fullScan(_ root: URL) async -> DiskScanResult {
        let store = DiskIndexStore()
        return await store.rebuild(root: root.path, progress: ScanProgress())!
    }

    private func expectMatches(
        _ incremental: DiskScanResult,
        _ full: DiskScanResult,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            incremental.totalBytes == full.totalBytes,
            "\(label): total bytes drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            incremental.filesScanned == full.filesScanned,
            "\(label): file count drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            incremental.categoryBytes == full.categoryBytes,
            "\(label): per-type bytes drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            incremental.categoryCounts == full.categoryCounts,
            "\(label): per-type counts drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            incremental.bucketBytes == full.bucketBytes,
            "\(label): per-size-class bytes drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            incremental.tree.sizes == full.tree.sizes,
            "\(label): folder sizes drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            incremental.tree.children == full.tree.children,
            "\(label): tree shape drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            incremental.largestFiles.map(\.path) == full.largestFiles.map(\.path),
            "\(label): largest-files list drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            incremental.childSizes == full.childSizes,
            "\(label): top-level sizes drifted",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - The walk itself

    @Test("A cold walk rolls child bytes up into every ancestor")
    func coldWalkRollsUp() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let scan = await fullScan(root)

        #expect(scan.filesScanned == 6)

        let photos = scan.tree.sizes[root.appendingPathComponent("photos").path] ?? 0
        let code = scan.tree.sizes[root.appendingPathComponent("code").path] ?? 0
        let deep = scan.tree.sizes[root.appendingPathComponent("code/src").path] ?? 0

        #expect(photos >= 100 * 1024)
        // The parent must contain its subfolder's bytes, not just its own files.
        #expect(code > deep)
        #expect(deep >= 4 * 1024)
        #expect(scan.totalBytes >= photos + code)
        // An empty folder is indexed but carries no bytes, so charts skip it.
        #expect(scan.tree.sizes[root.appendingPathComponent("empty").path] == 0)
    }

    // MARK: - Incremental equals full

    @Test("Adding a file updates its folder and every ancestor")
    func addFile() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiskIndexStore()
        _ = await store.rebuild(root: root.path, progress: ScanProgress())

        try write(root.appendingPathComponent("code/src/extra.swift"), kb: 120)

        var batch = DiskChangeBatch()
        batch.dirs.insert(root.appendingPathComponent("code/src").path)
        let incremental = await store.apply(batch)

        let full = await fullScan(root)
        #expect(incremental != nil)
        expectMatches(incremental!, full, "add file")
    }

    @Test("Deleting a file gives its bytes back at every level")
    func deleteFile() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiskIndexStore()
        _ = await store.rebuild(root: root.path, progress: ScanProgress())

        try FileManager.default.removeItem(at: root.appendingPathComponent("photos/b.jpg"))

        var batch = DiskChangeBatch()
        batch.dirs.insert(root.appendingPathComponent("photos").path)
        let incremental = await store.apply(batch)

        let full = await fullScan(root)
        #expect(incremental != nil)
        expectMatches(incremental!, full, "delete file")
    }

    @Test("Deleting the biggest file rebuilds the top-N list from the pool")
    func deleteLargestFile() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiskIndexStore()
        let before = await store.rebuild(root: root.path, progress: ScanProgress())!
        #expect(before.largestFiles.first?.name == "movie.mp4")

        try FileManager.default.removeItem(at: root.appendingPathComponent("movie.mp4"))

        var batch = DiskChangeBatch()
        batch.dirs.insert(root.path)
        let incremental = await store.apply(batch)!

        // The list must re-rank rather than keep a dangling entry.
        #expect(!incremental.largestFiles.contains { $0.name == "movie.mp4" })
        expectMatches(incremental, await fullScan(root), "delete largest")
    }

    @Test("A file changing size moves the delta, not the whole total")
    func resizeFile() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiskIndexStore()
        _ = await store.rebuild(root: root.path, progress: ScanProgress())

        try write(root.appendingPathComponent("photos/a.jpg"), kb: 500)

        var batch = DiskChangeBatch()
        batch.dirs.insert(root.appendingPathComponent("photos").path)
        let incremental = await store.apply(batch)

        #expect(incremental != nil)
        expectMatches(incremental!, await fullScan(root), "resize file")
    }

    @Test("A brand-new folder is walked once and folded in under its parent")
    func addDirectory() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiskIndexStore()
        _ = await store.rebuild(root: root.path, progress: ScanProgress())

        let new = root.appendingPathComponent("archive/2026")
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try write(new.appendingPathComponent("backup.zip"), kb: 700)
        try write(new.appendingPathComponent("notes.txt"), kb: 3)

        // FSEvents reports the created directory and its parent.
        var batch = DiskChangeBatch()
        batch.dirs.insert(root.path)
        batch.dirs.insert(root.appendingPathComponent("archive").path)
        batch.dirs.insert(new.path)
        let incremental = await store.apply(batch)

        #expect(incremental != nil)
        expectMatches(incremental!, await fullScan(root), "add directory")
    }

    @Test("Removing a folder unwinds its whole subtree, not just its own files")
    func deleteDirectory() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiskIndexStore()
        _ = await store.rebuild(root: root.path, progress: ScanProgress())

        try FileManager.default.removeItem(at: root.appendingPathComponent("code"))

        var batch = DiskChangeBatch()
        batch.dirs.insert(root.appendingPathComponent("code").path)
        batch.dirs.insert(root.path)
        let incremental = await store.apply(batch)

        #expect(incremental != nil)
        expectMatches(incremental!, await fullScan(root), "delete directory")
    }

    @Test("A rename is an add and a remove, and nets out exactly")
    func renameFile() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiskIndexStore()
        _ = await store.rebuild(root: root.path, progress: ScanProgress())

        try FileManager.default.moveItem(
            at: root.appendingPathComponent("photos/a.jpg"),
            to: root.appendingPathComponent("code/moved.jpg")
        )

        var batch = DiskChangeBatch()
        batch.dirs.insert(root.appendingPathComponent("photos").path)
        batch.dirs.insert(root.appendingPathComponent("code").path)
        let incremental = await store.apply(batch)

        #expect(incremental != nil)
        expectMatches(incremental!, await fullScan(root), "rename across folders")
    }

    @Test("mustScanSubDirs rewalks only the named subtree and still lands exact")
    func coarseSubtreeEvent() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiskIndexStore()
        _ = await store.rebuild(root: root.path, progress: ScanProgress())

        // A burst the kernel couldn't describe: several changes at once.
        try write(root.appendingPathComponent("code/src/one.swift"), kb: 30)
        try write(root.appendingPathComponent("code/src/two.swift"), kb: 30)
        try FileManager.default.removeItem(at: root.appendingPathComponent("code/main.swift"))

        var batch = DiskChangeBatch()
        batch.subtrees.insert(root.appendingPathComponent("code").path)
        let incremental = await store.apply(batch)

        #expect(incremental != nil)
        expectMatches(incremental!, await fullScan(root), "coarse subtree")
    }

    @Test("Many rounds of edits don't accumulate drift")
    func repeatedUpdatesStayExact() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiskIndexStore()
        _ = await store.rebuild(root: root.path, progress: ScanProgress())

        // Drift is cumulative by nature, so one update proving out isn't
        // enough — the interesting failure appears after many.
        for round in 0..<12 {
            let folder = root.appendingPathComponent(round.isMultiple(of: 2) ? "photos" : "code/src")
            let file = folder.appendingPathComponent("churn-\(round).bin")
            try write(file, kb: 20 + round * 5)

            var batch = DiskChangeBatch()
            batch.dirs.insert(folder.path)
            _ = await store.apply(batch)

            if round.isMultiple(of: 3) {
                try FileManager.default.removeItem(at: file)
                var removal = DiskChangeBatch()
                removal.dirs.insert(folder.path)
                _ = await store.apply(removal)
            }
        }

        let incremental = await store.snapshot()
        #expect(incremental != nil)
        expectMatches(incremental!, await fullScan(root), "12 rounds")
    }

    @Test("An unreadable folder keeps its cached size instead of dropping to zero")
    func unreadableFolderKeepsCache() async throws {
        let root = try makeTree()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: root.appendingPathComponent("photos").path
            )
            try? FileManager.default.removeItem(at: root)
        }

        let store = DiskIndexStore()
        let before = await store.rebuild(root: root.path, progress: ScanProgress())!
        let photos = root.appendingPathComponent("photos").path
        let cached = before.tree.sizes[photos] ?? 0
        #expect(cached > 0)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: photos)

        var batch = DiskChangeBatch()
        batch.dirs.insert(photos)
        _ = await store.apply(batch)

        let after = await store.snapshot()!
        // Zeroing the folder out on a permission blip would be a visible lie.
        #expect(after.tree.sizes[photos] == cached)
    }

    // MARK: - Geometry

    @Test("Ancestor walk stops at the scan root")
    func parentChainStopsAtRoot() {
        let index = DiskIndex(root: "/Users/me/Downloads")
        #expect(index.depth(of: "/Users/me/Downloads") == 0)
        #expect(index.depth(of: "/Users/me/Downloads/a") == 1)
        #expect(index.depth(of: "/Users/me/Downloads/a/b/c") == 3)
        // Outside the root entirely — must never be folded in.
        #expect(index.depth(of: "/Users/me/Documents/x") == .max)
        #expect(DiskIndex.parent(of: "/Users/me/Downloads/a") == "/Users/me/Downloads")
        #expect(DiskIndex.parent(of: "/") == nil)
    }

    @Test("A trailing slash on the root doesn't create a phantom level")
    func rootSlashNormalised() {
        #expect(DiskIndex(root: "/Users/me/Downloads/").root == "/Users/me/Downloads")
        #expect(DiskIndex(root: "/").root == "/")
    }
}

/// A flat folder of many files is the normal shape of Downloads, and it's the
/// case a per-directory top-N cap would silently break — the list would show
/// five entries instead of forty with no error anywhere.
struct LargestFilesTests {
    @Test("A flat folder of 60 files still fills the whole largest-files list")
    func flatFolderFillsList() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flightdeck-flat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 1...60 {
            try Data(repeating: 0x41, count: index * 8 * 1024)
                .write(to: root.appendingPathComponent("file-\(index).bin"))
        }

        let canonical = URL(fileURLWithPath: DiskIndex.canonical(root))
        let store = DiskIndexStore()
        let scan = await store.rebuild(root: canonical.path, progress: ScanProgress())!

        #expect(scan.largestFiles.count == DiskIndex.displayedTopFiles)
        #expect(scan.largestFiles.first?.name == "file-60.bin")
        // Strictly descending, with no duplicates.
        let sizes = scan.largestFiles.map(\.bytes)
        #expect(sizes == sizes.sorted(by: >))
        #expect(Set(scan.largestFiles.map(\.path)).count == scan.largestFiles.count)

        // And it must survive an incremental update of that same flat folder.
        try Data(repeating: 0x41, count: 4 * 1024 * 1024)
            .write(to: root.appendingPathComponent("whale.bin"))
        var batch = DiskChangeBatch()
        batch.dirs.insert(canonical.path)
        let after = await store.apply(batch)!

        #expect(after.largestFiles.first?.name == "whale.bin")
        #expect(after.largestFiles.count == DiskIndex.displayedTopFiles)
    }
}

/// FSEvents is the part that can't be reasoned about — either the kernel
/// delivers the path or the whole scheme is dead. This exercises the real
/// stream rather than a stub.
struct DiskWatcherTests {
    @Test("The watcher reports the directory a new file landed in", .timeLimit(.minutes(1)))
    func reportsChangedDirectory() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flightdeck-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("inner"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let canonical = DiskIndex.canonical(root)
        let watcher = DiskWatcher()
        let inbox = BatchInbox()

        watcher.start(root: canonical, replayingHistory: false) { batch in
            inbox.deliver(batch)
        }
        #expect(watcher.isRunning)
        defer { watcher.stop() }

        // FSEvents only reports changes made after the stream is live.
        try await Task.sleep(for: .milliseconds(400))
        try Data(repeating: 0x41, count: 2048)
            .write(to: root.appendingPathComponent("inner/new.bin"))

        let expected = canonical + "/inner"
        var seen = false
        for _ in 0..<40 where !seen {
            try await Task.sleep(for: .milliseconds(150))
            seen = inbox.paths.contains(expected)
        }

        #expect(seen, "FSEvents never reported \(expected); saw \(inbox.paths)")
        // And the cursor has to be persisted, or a restart can't replay.
        #expect(DiskWatcher.canReplay(root: canonical))
        DiskWatcher.clearCursor(for: canonical)
    }
}

/// The watcher hands batches over on its own queue; this collects them for the
/// test to poll.
private final class BatchInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: Set<String> = []

    var paths: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    func deliver(_ batch: DiskChangeBatch) {
        lock.lock()
        seen.formUnion(batch.dirs)
        seen.formUnion(batch.subtrees)
        lock.unlock()
    }
}
