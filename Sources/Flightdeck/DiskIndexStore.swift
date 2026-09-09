import Foundation

/// Owns the index and is the only thing allowed to mutate it. An actor rather
/// than a lock because every caller is already async: the initial walk, the
/// FSEvents batches, and the periodic reconcile all arrive from different
/// places and must not interleave.
actor DiskIndexStore {
    private var index: DiskIndex?

    var indexedRoot: String? { index?.root }

    func reset() {
        index = nil
    }

    /// Full walk. Unavoidable once — for the first look at a root, and as the
    /// periodic correction for drift.
    func rebuild(root: String, progress: ScanProgress) -> DiskScanResult? {
        guard let built = Self.walk(root: root, progress: progress) else { return nil }
        index = built
        return built.snapshot()
    }

    /// The incremental path: re-read only the directories FSEvents named, plus
    /// walk any subtree the kernel couldn't describe precisely.
    ///
    /// Returns `nil` when nothing actually moved, so the UI isn't republished
    /// for a no-op (a file's mtime changing without its size changing is very
    /// common — editors touch files constantly).
    func apply(_ batch: DiskChangeBatch) -> DiskScanResult? {
        guard var current = index else { return nil }
        let before = current.recursive[current.root] ?? 0
        let filesBefore = current.totalFiles
        var touched = false

        for path in batch.subtrees {
            guard let subtree = Self.locate(path, in: current) else { continue }
            if subtree == current.root {
                // Nothing cached still applies. Caller re-runs a full scan.
                index = nil
                return nil
            }
            if rewalk(subtree, into: &current) { touched = true }
        }

        // Shallowest first: a parent's subdirectory reconciliation folds in a
        // whole new tree at once, and the children's own events then find
        // everything already cached and become cheap no-ops.
        let inside = batch.dirs.compactMap { Self.locate($0, in: current) }
        for dir in inside.sorted(by: { current.depth(of: $0) < current.depth(of: $1) }) {
            if reread(dir, into: &current) { touched = true }
        }

        index = current
        guard touched
            || current.recursive[current.root] ?? 0 != before
            || current.totalFiles != filesBefore
        else { return nil }
        return current.snapshot()
    }

    func snapshot() -> DiskScanResult? {
        index?.snapshot()
    }

    /// Maps an incoming path onto the spelling this index uses, or `nil` if it
    /// falls outside the scan root.
    ///
    /// FSEvents reports canonical paths, so this is normally the identity — but
    /// a caller passing `/tmp/x` instead of `/private/tmp/x` would otherwise be
    /// dropped silently, and a silently-ignored change is the worst failure this
    /// design can have.
    private static func locate(_ path: String, in index: DiskIndex) -> String? {
        if index.depth(of: path) != .max { return path }

        let resolved = DiskIndex.canonical(URL(fileURLWithPath: path))
        if index.depth(of: resolved) != .max { return resolved }

        // A path that has just been deleted can't be canonicalised on its own;
        // its parent usually still can be.
        guard let parent = DiskIndex.parent(of: path) else { return nil }
        let viaParent = DiskIndex.canonical(URL(fileURLWithPath: parent))
            + "/" + URL(fileURLWithPath: path).lastPathComponent
        return index.depth(of: viaParent) != .max ? viaParent : nil
    }

    // MARK: - One directory

    /// - Returns: whether anything about the directory actually changed.
    private func reread(_ dir: String, into index: inout DiskIndex) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir, isDirectory: &isDirectory)

        // Gone, or replaced by a file where a directory used to be.
        if !exists || !isDirectory.boolValue {
            guard index.direct[dir] != nil else { return false }
            index.remove(subtree: dir)
            return true
        }

        // Appeared. We have no cached size for anything inside it, so this one
        // does need a walk — but only of the new subtree.
        guard let cached = index.direct[dir] else {
            return rewalk(dir, into: &index)
        }

        // Unreadable now (permissions, a volume going away). Keeping the stale
        // numbers is strictly better than zeroing the folder out.
        guard let read = DiskIndex.read(directory: dir, keepEveryFile: index.keepsEveryFile(at: dir)) else {
            return false
        }

        var changed = false
        if read.facts.bytes != cached.bytes || read.facts.files != cached.files {
            index.install(read.facts, offering: read.files, at: dir)
            changed = true
        } else if read.facts.allFiles != cached.allFiles {
            // Same total from a different set of files — a swap, or two changes
            // that happen to cancel out. The totals are right but the names
            // aren't, and the charts label individual files.
            index.install(read.facts, offering: read.files, at: dir)
            changed = true
        }

        let known = index.subdirs[dir] ?? []
        for gone in known.subtracting(read.subdirs) {
            index.remove(subtree: gone)
            changed = true
        }
        for added in read.subdirs.subtracting(known) {
            if rewalk(added, into: &index) { changed = true }
        }
        return changed
    }

    /// Replaces a subtree wholesale: drop what we cached, walk it, fold it back
    /// in. Used for new directories and for `mustScanSubDirs`.
    private func rewalk(_ dir: String, into index: inout DiskIndex) -> Bool {
        if index.direct[dir] != nil {
            index.remove(subtree: dir)
        }
        guard FileManager.default.fileExists(atPath: dir),
              let fresh = Self.walk(root: dir, progress: ScanProgress())
        else { return true }
        index.merge(fresh, at: dir)
        return true
    }

    // MARK: - The walk

    /// Enumerates a tree into per-directory facts. Directories are recorded as
    /// they're visited (so empty ones exist in the index), and every file lands
    /// on its immediate parent — recursive totals come later, from the rollup.
    private static func walk(root: String, progress: ScanProgress) -> DiskIndex? {
        // The enumerator yields canonical paths, so the root has to be
        // canonical too or nothing beneath it matches: /tmp and /var are
        // symlinks, and so is any folder reached through one. Every ancestor
        // walk would then run past the root instead of stopping at it.
        let rootURL = URL(fileURLWithPath: DiskIndex.canonical(URL(fileURLWithPath: root)))
        let skipped = SkipTally()

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: walkKeys,
            // Hidden files stay in — caches and dotfiles are exactly what eats
            // space unnoticed.
            options: [],
            errorHandler: { _, _ in
                skipped.bump()
                return true
            }
        ) else { return nil }

        var index = DiskIndex(root: rootURL.path)
        var direct: [String: DirFacts] = [index.root: DirFacts()]
        var links: [String: Set<String>] = [:]
        if index.keepsEveryFile(at: index.root) { direct[index.root]?.allFiles = [:] }

        var files = 0
        var bytes: Int64 = 0
        let keySet = Set(walkKeys)

        // The biggest-files pool, maintained globally as we go: a file only
        // enters if it beats the current cutoff, and the array is trimmed in
        // batches rather than sorted on every insert.
        var pool: [ScannedFile] = []
        var cutoff: Int64 = 0

        // nextObject() rather than for-in: iterating an NSEnumerator needs
        // makeIterator, which isn't available in an async context.
        while let object = enumerator.nextObject() {
            if Task.isCancelled { return nil }
            guard let url = object as? URL else { continue }

            let values = try? url.resourceValues(forKeys: keySet)
            if values?.isSymbolicLink == true { continue }

            let path = url.path
            guard let parent = DiskIndex.parent(of: path) else { continue }

            if values?.isDirectory == true {
                links[parent, default: []].insert(path)
                if direct[path] == nil {
                    var facts = DirFacts()
                    if index.keepsEveryFile(at: path) { facts.allFiles = [:] }
                    direct[path] = facts
                }
                continue
            }

            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            if direct[parent] == nil {
                var facts = DirFacts()
                if index.keepsEveryFile(at: parent) { facts.allFiles = [:] }
                direct[parent] = facts
            }
            let name = url.lastPathComponent
            direct[parent]?.absorb(name: name, size: size)

            if pool.count < DiskIndex.candidatePool || size > cutoff {
                pool.append(ScannedFile(path: path, name: name, bytes: size))
                if pool.count >= DiskIndex.candidatePool * 2 {
                    pool.sort(by: ScannedFile.ranks)
                    pool.removeLast(pool.count - DiskIndex.candidatePool)
                    cutoff = pool.last?.bytes ?? 0
                }
            }

            files += 1
            bytes += size
            if files % 2000 == 0 { progress.set(files: files, bytes: bytes) }
        }

        index.load(direct: direct, subdirs: links, pool: pool)
        index.note(skipped: skipped.value)
        return index
    }

    private static let walkKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey,
    ]
}

/// FileManager's errorHandler runs synchronously on the walking thread; a
/// reference box keeps the count without capturing a mutable local.
private final class SkipTally: @unchecked Sendable {
    private(set) var value = 0
    func bump() { value += 1 }
}

/// Counters for a walk in flight. Locked rather than unchecked-and-hoped:
/// the UI polls these on the main thread while the walk writes them.
final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0

    var reading: (files: Int, bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        return (files, bytes)
    }

    func set(files: Int, bytes: Int64) {
        lock.lock()
        self.files = files
        self.bytes = bytes
        lock.unlock()
    }
}
