import Foundation

extension ScannedFile {
    /// Biggest first, then by path. The tie-break isn't cosmetic: Swift's sort
    /// isn't stable, so without it equal-sized files come out in a different
    /// order after an incremental update than after a full rescan, and the two
    /// stop being comparable at all.
    static func ranks(_ lhs: ScannedFile, _ rhs: ScannedFile) -> Bool {
        lhs.bytes == rhs.bytes ? lhs.path < rhs.path : lhs.bytes > rhs.bytes
    }
}

/// What one directory contributes on its own: the bytes of the files sitting
/// directly inside it, never its subfolders.
///
/// This split is the whole trick behind incremental updates. Recursive folder
/// sizes are *derived* by summing these up the tree, so when a file changes we
/// re-read exactly one directory and adjust its ancestors — instead of walking
/// the disk again.
struct DirFacts: Sendable {
    var bytes: Int64 = 0
    var files = 0
    var categoryBytes: [FileCategory: Int64] = [:]
    var categoryCounts: [FileCategory: Int] = [:]
    var bucketBytes: [SizeBucket: Int64] = [:]
    var bucketCounts: [SizeBucket: Int] = [:]
    /// Every direct file, but only for directories shallow enough that the
    /// charts can drill into them. Deep directories keep aggregates only — an
    /// exact per-file index of `/` would cost hundreds of megabytes.
    var allFiles: [String: Int64]?

    mutating func absorb(name: String, size: Int64) {
        bytes += size
        files += 1
        let category = FileCategory.of(path: name)
        categoryBytes[category, default: 0] += size
        categoryCounts[category, default: 0] += 1
        let bucket = SizeBucket.of(size)
        bucketBytes[bucket, default: 0] += size
        bucketCounts[bucket, default: 0] += 1
        allFiles?[name] = size
    }
}

/// The mutable model behind the charts. Directory-granular, so a change costs
/// one shallow directory listing plus a walk up the ancestor chain.
struct DiskIndex: Sendable {
    let root: String
    private let rootSlash: String

    /// Direct (non-recursive) facts per directory.
    private(set) var direct: [String: DirFacts] = [:]
    /// Immediate subdirectories per directory.
    private(set) var subdirs: [String: Set<String>] = [:]
    /// Recursive bytes per directory — maintained by delta, never recomputed.
    private(set) var recursive: [String: Int64] = [:]

    // Running global aggregates, so a snapshot never sums over every directory.
    private(set) var totalFiles = 0
    private(set) var categoryBytes: [FileCategory: Int64] = [:]
    private(set) var categoryCounts: [FileCategory: Int] = [:]
    private(set) var bucketBytes: [SizeBucket: Int64] = [:]
    private(set) var bucketCounts: [SizeBucket: Int] = [:]
    private(set) var skipped = 0

    /// The biggest files anywhere in the tree, kept deeper than the 40 we
    /// display so deletions eat the slack instead of shortening the list.
    ///
    /// Nothing is retained per directory: whenever a directory is re-read, its
    /// whole listing is offered here and then discarded. That's what keeps the
    /// list exact without an index of every file on disk — a per-directory
    /// top-N would quietly truncate it for a flat folder of hundreds of files,
    /// which is exactly what Downloads looks like.
    private(set) var candidates: [ScannedFile] = []
    static let candidatePool = 240
    static let displayedTopFiles = 40
    static let maxDepth = 4

    /// Enough files have been deleted that the pool can no longer fill the
    /// displayed list, so only a full walk can restore it.
    var needsTopFilesRepair: Bool {
        candidates.count < Self.displayedTopFiles && totalFiles > candidates.count
    }

    init(root: String) {
        self.root = root.hasSuffix("/") && root.count > 1 ? String(root.dropLast()) : root
        self.rootSlash = self.root == "/" ? "/" : self.root + "/"
    }

    // MARK: - Geometry

    /// Levels below the scan root. `.max` for anything outside it.
    func depth(of path: String) -> Int {
        if path == root { return 0 }
        guard path.hasPrefix(rootSlash) else { return .max }
        return path.dropFirst(rootSlash.count).reduce(1) { $1 == "/" ? $0 + 1 : $0 }
    }

    func keepsEveryFile(at dir: String) -> Bool {
        depth(of: dir) < Self.maxDepth
    }

    /// The spelling of a path that `FileManager`'s enumerator will use.
    ///
    /// Not `resolvingSymlinksInPath()`: Foundation documents that one as
    /// *stripping* a leading `/private`, so it turns the canonical
    /// `/private/var/x` back into the symlink `/var/x` — the opposite of what
    /// the enumerator yields. Getting this wrong silently breaks every rollup,
    /// because a child path then doesn't share a prefix with its own root.
    static func canonical(_ url: URL) -> String {
        let resolved = (try? url.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath
        return resolved ?? url.path
    }

    static func parent(of path: String) -> String? {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return nil }
        return String(path[path.startIndex..<slash])
    }

    // MARK: - Mutation

    /// Replaces one directory's facts and propagates the byte delta upward.
    ///
    /// - Parameter offering: the directory's current files, compared against the
    ///   global pool and then dropped.
    mutating func install(_ facts: DirFacts, offering files: [ScannedFile], at dir: String) {
        let old = direct[dir]
        direct[dir] = facts

        if let old {
            subtract(old)
            candidates.removeAll { Self.parent(of: $0.path) == dir }
        }
        add(facts)
        offer(files)

        addBytes(facts.bytes - (old?.bytes ?? 0), from: dir)
    }

    /// Drops a directory and everything cached beneath it, unwinding its bytes
    /// and aggregate contributions on the way out.
    mutating func remove(subtree dir: String) {
        var stack = [dir]
        var doomed: [String] = []
        while let current = stack.popLast() {
            doomed.append(current)
            if let kids = subdirs[current] { stack.append(contentsOf: kids) }
        }

        let vanished = recursive[dir] ?? 0

        for path in doomed {
            if let facts = direct[path] { subtract(facts) }
            direct[path] = nil
            subdirs[path] = nil
            recursive[path] = nil
        }

        let doomedSet = Set(doomed)
        candidates.removeAll { file in
            guard let parent = Self.parent(of: file.path) else { return false }
            return doomedSet.contains(parent)
        }

        if let parent = Self.parent(of: dir) {
            subdirs[parent]?.remove(dir)
            addBytes(-vanished, from: parent)
        }
    }

    /// Folds a freshly-walked subtree in — used when a directory appears that
    /// we have no cached size for.
    mutating func merge(_ other: DiskIndex, at dir: String) {
        for (path, kids) in other.subdirs {
            subdirs[path, default: []].formUnion(kids)
        }
        // Recursive totals inside the subtree are already correct; copy them
        // wholesale, then push the subtree's own total up our chain.
        for (path, bytes) in other.recursive where path != dir {
            recursive[path] = bytes
        }
        for (path, facts) in other.direct where path != dir {
            direct[path] = facts
            add(facts)
        }
        offer(other.candidates.filter { Self.parent(of: $0.path) != dir })

        // The subtree root goes through install() so its own bytes and its
        // descendants' rolled-up total each land on our ancestors exactly once.
        let descendants = (other.recursive[dir] ?? 0) - (other.direct[dir]?.bytes ?? 0)
        let rootFiles = other.candidates.filter { Self.parent(of: $0.path) == dir }
        install(other.direct[dir] ?? DirFacts(), offering: rootFiles, at: dir)
        addBytes(descendants, from: dir)

        if let parent = Self.parent(of: dir), dir != root {
            subdirs[parent, default: []].insert(dir)
        }
    }

    mutating func note(skipped count: Int) {
        skipped = count
    }

    /// Bulk load from a completed walk. Going through `install()` per directory
    /// would re-sort the candidate pool tens of thousands of times.
    mutating func load(
        direct loaded: [String: DirFacts],
        subdirs links: [String: Set<String>],
        pool: [ScannedFile]
    ) {
        direct = loaded
        subdirs = links
        recursive = [:]
        totalFiles = 0
        categoryBytes = [:]
        categoryCounts = [:]
        bucketBytes = [:]
        bucketCounts = [:]

        for dir in loaded.keys { recursive[dir] = 0 }
        recursive[root] = 0

        for (dir, facts) in loaded {
            add(facts)
            guard facts.bytes != 0 else { continue }
            var cursor: String? = dir
            while let path = cursor {
                recursive[path, default: 0] += facts.bytes
                if path == root { break }
                cursor = Self.parent(of: path)
            }
        }

        candidates = pool.sorted(by: ScannedFile.ranks)
        if candidates.count > Self.candidatePool {
            candidates.removeLast(candidates.count - Self.candidatePool)
        }
    }

    // MARK: - Aggregate bookkeeping

    private mutating func add(_ facts: DirFacts) {
        for (key, value) in facts.categoryBytes { categoryBytes[key, default: 0] += value }
        for (key, value) in facts.categoryCounts { categoryCounts[key, default: 0] += value }
        for (key, value) in facts.bucketBytes { bucketBytes[key, default: 0] += value }
        for (key, value) in facts.bucketCounts { bucketCounts[key, default: 0] += value }
        totalFiles += facts.files
    }

    private mutating func subtract(_ facts: DirFacts) {
        for (key, value) in facts.categoryBytes { categoryBytes[key, default: 0] -= value }
        for (key, value) in facts.categoryCounts { categoryCounts[key, default: 0] -= value }
        for (key, value) in facts.bucketBytes { bucketBytes[key, default: 0] -= value }
        for (key, value) in facts.bucketCounts { bucketCounts[key, default: 0] -= value }
        totalFiles -= facts.files
    }

    private mutating func offer(_ files: [ScannedFile]) {
        guard !files.isEmpty else { return }
        candidates.append(contentsOf: files)
        candidates.sort(by: ScannedFile.ranks)
        if candidates.count > Self.candidatePool {
            candidates.removeLast(candidates.count - Self.candidatePool)
        }
    }

    /// Walks from a directory up to the scan root, moving every ancestor's
    /// recursive total. This is the O(depth) step that replaces the O(files)
    /// rescan.
    private mutating func addBytes(_ delta: Int64, from dir: String) {
        guard delta != 0 else { return }
        var cursor: String? = dir
        while let path = cursor {
            recursive[path, default: 0] += delta
            if path == root { break }
            cursor = Self.parent(of: path)
        }
    }

    // MARK: - Derived output

    /// Flattens into the immutable shape the charts read. Only the shallow part
    /// of the tree is materialised — that's all the charts can display.
    func snapshot() -> DiskScanResult {
        var result = DiskScanResult()
        result.totalBytes = recursive[root] ?? 0
        result.filesScanned = totalFiles
        result.skipped = skipped
        result.categoryBytes = categoryBytes.filter { $0.value > 0 }
        result.categoryCounts = categoryCounts.filter { $0.value > 0 }
        result.bucketBytes = bucketBytes.filter { $0.value > 0 }
        result.bucketCounts = bucketCounts.filter { $0.value > 0 }
        result.largestFiles = Array(candidates.prefix(Self.displayedTopFiles))

        var tree = DiskTree()
        for (dir, bytes) in recursive {
            let level = depth(of: dir)
            guard level <= Self.maxDepth else { continue }
            tree.sizes[dir] = bytes
            if level > 0, let parent = Self.parent(of: dir) {
                tree.children[parent, default: []].insert(dir)
            }
            // Files appear as leaves alongside folders, so drilling into a
            // folder reveals the one huge file rather than an empty level.
            if level < Self.maxDepth, let files = direct[dir]?.allFiles {
                for (name, size) in files where size > 0 {
                    let path = dir == "/" ? "/" + name : dir + "/" + name
                    tree.sizes[path] = size
                    tree.children[dir, default: []].insert(path)
                }
            }
        }
        result.tree = tree

        for child in subdirs[root] ?? [] {
            result.childSizes[child] = recursive[child] ?? 0
        }
        for (name, size) in direct[root]?.allFiles ?? [:] {
            result.childSizes[root == "/" ? "/" + name : root + "/" + name] = size
        }

        return result
    }
}

// MARK: - Reading one directory

extension DiskIndex {
    private static let listKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey,
    ]

    /// Shallow read of a single directory: its own files' facts, the names of
    /// its subdirectories, and its files as pool candidates.
    ///
    /// `nil` means unreadable — the caller must keep the cached facts rather
    /// than treat it as empty, or a permission blip would silently zero out a
    /// folder that's still full.
    static func read(
        directory dir: String,
        keepEveryFile: Bool
    ) -> (facts: DirFacts, subdirs: Set<String>, files: [ScannedFile])? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: dir),
            includingPropertiesForKeys: listKeys,
            options: []
        ) else { return nil }

        var facts = DirFacts()
        var kids: Set<String> = []
        var files: [ScannedFile] = []
        if keepEveryFile { facts.allFiles = [:] }
        let keySet = Set(listKeys)

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: keySet)
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true {
                kids.insert(entry.path)
                continue
            }

            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            let name = entry.lastPathComponent
            facts.absorb(name: name, size: size)
            files.append(ScannedFile(path: entry.path, name: name, bytes: size))
        }

        return (facts, kids, files)
    }
}
