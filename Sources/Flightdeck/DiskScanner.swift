import AppKit
import Foundation

struct ScannedFile: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let bytes: Int64
}

/// Size classes for the distribution chart — answers whether space is eaten
/// by a few giants or a mountain of mid-sized files.
enum SizeBucket: String, CaseIterable, Sendable {
    case tiny, small, medium, large, huge

    var label: String {
        switch self {
        case .tiny:   return "<1M"
        case .small:  return "1-10M"
        case .medium: return "10-100M"
        case .large:  return "0.1-1G"
        case .huge:   return ">1G"
        }
    }

    static func of(_ bytes: Int64) -> SizeBucket {
        switch bytes {
        case ..<1_048_576:       return .tiny
        case ..<10_485_760:      return .small
        case ..<104_857_600:     return .medium
        case ..<1_073_741_824:   return .large
        default:                 return .huge
        }
    }
}

/// Path-keyed sizes plus parent→children links, capped in depth. A flat
/// lookup rather than nested structs: the charts only ever ask for one level
/// at a time, and drilling is just changing which path is the focus.
struct DiskTree: Sendable {
    var sizes: [String: Int64] = [:]
    var children: [String: Set<String>] = [:]

    func childNodes(of path: String) -> [(path: String, name: String, bytes: Int64, hasChildren: Bool)] {
        (children[path] ?? []).map { child in
            (
                path: child,
                name: URL(fileURLWithPath: child).lastPathComponent,
                bytes: sizes[child] ?? 0,
                hasChildren: !(children[child] ?? []).isEmpty
            )
        }
        .filter { $0.bytes > 0 }
        .sorted { $0.bytes > $1.bytes }
    }
}

struct DiskScanResult: Sendable {
    var tree = DiskTree()
    var childSizes: [String: Int64] = [:]
    var largestFiles: [ScannedFile] = []
    var totalBytes: Int64 = 0
    var filesScanned = 0
    var skipped = 0
    /// Bytes per file type and per size class, for the charts.
    var categoryBytes: [FileCategory: Int64] = [:]
    var categoryCounts: [FileCategory: Int] = [:]
    var bucketBytes: [SizeBucket: Int64] = [:]
    var bucketCounts: [SizeBucket: Int] = [:]
}

/// Recursive disk usage for a directory — walked once, then kept current.
///
/// The walk is the expensive part (minutes on a big tree), so it happens once
/// per root. After that `DiskWatcher` reports which directories changed and
/// `DiskIndexStore` re-reads only those, adjusting their ancestors' totals by
/// the difference. A file appearing in a folder costs one directory listing and
/// a walk up four parents, not another pass over the disk.
///
/// The one thing incremental tracking can't promise is that it never drifts:
/// hardlinks, clones, events the kernel coalesced away, and volumes that
/// disappear mid-flight all leave the cache slightly off. So a full walk still
/// runs periodically as the correction. Incremental for responsiveness, full
/// for truth.
@Observable
final class DiskScanner {
    private(set) var isScanning = false
    private(set) var scannedRoot: URL?
    private(set) var result = DiskScanResult()
    /// Live counters while a scan is in flight.
    private(set) var progressFiles = 0
    private(set) var progressBytes: Int64 = 0

    /// Live-tracking state, surfaced so the UI can say whether the numbers are
    /// being maintained or are a frozen snapshot.
    private(set) var isLive = false
    private(set) var lastChangeAt: Date?
    private(set) var lastReconcileAt: Date?
    private(set) var updatesApplied = 0
    private(set) var pendingDirectories = 0
    /// How long the last incremental update took — the number that justifies
    /// all of this over a rescan.
    private(set) var lastUpdateSeconds: TimeInterval?

    private let store = DiskIndexStore()
    private let watcher = DiskWatcher()

    private var task: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?
    private var pending = DiskChangeBatch()

    /// Long enough to collapse a burst (an unarchive, a build, a download
    /// finishing) into one update; short enough to feel immediate.
    private static let debounce: Duration = .milliseconds(450)
    /// The drift correction. Cheap to raise, and nothing depends on it being
    /// frequent — incremental updates carry the day-to-day truth.
    private static let reconcileInterval: TimeInterval = 2 * 3600

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Persists the FSEvents cursor, so the next launch can replay what
            // happened while we were closed instead of walking again.
            self?.watcher.stop()
        }
    }

    func scan(_ root: URL) {
        cancel()
        isScanning = true
        // Canonical form throughout: the index, the chart paths, and the paths
        // FSEvents reports all have to be the same spelling of the same folder.
        let root = URL(fileURLWithPath: DiskIndex.canonical(root))
        scannedRoot = root
        result = DiskScanResult()
        progressFiles = 0
        progressBytes = 0
        updatesApplied = 0
        lastChangeAt = nil

        let path = root.path
        let progress = ScanProgress()
        let store = self.store

        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isScanning else { return }
                let reading = progress.reading
                self.progressFiles = reading.files
                self.progressBytes = reading.bytes
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        task = Task { @MainActor [weak self] in
            let snapshot = await store.rebuild(root: path, progress: progress)
            guard let self, !Task.isCancelled else { return }
            if let snapshot {
                self.result = snapshot
                self.progressFiles = snapshot.filesScanned
                self.progressBytes = snapshot.totalBytes
                self.lastReconcileAt = Date()
            }
            self.isScanning = false
            self.progressTask?.cancel()
            // Fresh numbers, so start the stream from now rather than replaying
            // history we just observed directly.
            self.beginWatching(path, replayingHistory: false)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        progressTask?.cancel()
        progressTask = nil
        flushTask?.cancel()
        flushTask = nil
        reconcileTask?.cancel()
        reconcileTask = nil
        watcher.stop()
        isLive = false
        pendingDirectories = 0
        pending = DiskChangeBatch()
        isScanning = false
    }

    /// Recursive size for a row in the browser, if the current scan covered it.
    func size(forPath path: String) -> Int64? {
        result.tree.sizes[path] ?? result.childSizes[path]
    }

    func hasResults(for url: URL) -> Bool {
        scannedRoot?.path == url.path && !result.childSizes.isEmpty
    }

    /// Forces the drift correction now instead of waiting for the timer.
    func reconcileNow() {
        guard let root = scannedRoot, !isScanning else { return }
        let progress = ScanProgress()
        let store = self.store
        Task { @MainActor [weak self] in
            guard let snapshot = await store.rebuild(root: root.path, progress: progress),
                  let self else { return }
            self.result = snapshot
            self.lastReconcileAt = Date()
        }
    }

    // MARK: - Live tracking

    private func beginWatching(_ root: String, replayingHistory: Bool) {
        watcher.start(root: root, replayingHistory: replayingHistory) { [weak self] batch in
            // FSEvents calls back on its own queue; queue the batch up on the
            // main actor where the debounce and the published state live.
            Task { @MainActor in self?.enqueue(batch) }
        }
        isLive = watcher.isRunning
        beginReconciling()
    }

    private func enqueue(_ batch: DiskChangeBatch) {
        pending.merge(batch)
        pendingDirectories = pending.dirs.count + pending.subtrees.count

        flushTask?.cancel()
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        let batch = pending
        pending = DiskChangeBatch()
        pendingDirectories = 0
        guard !batch.isEmpty else { return }

        let started = Date()
        let snapshot = await store.apply(batch)
        lastUpdateSeconds = Date().timeIntervalSince(started)

        if let snapshot {
            result = snapshot
            lastChangeAt = Date()
            updatesApplied += 1
            return
        }

        // A nil snapshot is usually a no-op change (an editor touching a file
        // without changing its size). But if the index itself was thrown away —
        // the root moved, or the kernel lost the whole tree — only a full walk
        // can recover.
        if await store.indexedRoot == nil, let root = scannedRoot {
            scan(root)
        }
    }

    private func beginReconciling() {
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.reconcileInterval))
                guard !Task.isCancelled, let self, !self.isScanning else { continue }
                self.reconcileNow()
            }
        }
    }

    // MARK: - Cleanable Artifacts & Cache Radar

    private(set) var cleanables: [CleanableArtifact] = []
    private(set) var isScanningCleanables = false
    private(set) var totalCleanableBytes: Int64 = 0

    func scanCleanables() {
        guard !isScanningCleanables else { return }
        isScanningCleanables = true
        Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let targets: [(name: String, category: String, url: URL)] = [
                ("Xcode DerivedData", "DEV", home.appendingPathComponent("Library/Developer/Xcode/DerivedData")),
                ("Xcode Archives", "DEV", home.appendingPathComponent("Library/Developer/Xcode/Archives")),
                ("Swift PM Caches", "DEV", home.appendingPathComponent("Library/Caches/org.swift.swiftpm")),
                ("CocoaPods Cache", "PACKAGE", home.appendingPathComponent("Library/Caches/CocoaPods")),
                ("Homebrew Cache", "SYSTEM", home.appendingPathComponent("Library/Caches/Homebrew")),
                ("Yarn Cache", "PACKAGE", home.appendingPathComponent("Library/Caches/yarn")),
                ("NPM Cache", "PACKAGE", home.appendingPathComponent(".npm")),
                ("Rust Cargo Registry", "PACKAGE", home.appendingPathComponent(".cargo/registry")),
                ("User App Caches", "SYSTEM", home.appendingPathComponent("Library/Caches")),
            ]

            var found: [CleanableArtifact] = []
            for target in targets {
                guard FileManager.default.fileExists(atPath: target.url.path) else { continue }
                var totalBytes: Int64 = 0
                var count = 0
                if let enumerator = FileManager.default.enumerator(
                    at: target.url,
                    includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                           !(values.isDirectory ?? false) {
                            totalBytes += Int64(values.fileSize ?? 0)
                            count += 1
                        }
                    }
                }
                if totalBytes > 10_000_000 { // Only show caches > 10 MB
                    found.append(CleanableArtifact(
                        name: target.name,
                        category: target.category,
                        path: target.url.path,
                        bytes: totalBytes,
                        fileCount: count
                    ))
                }
            }

            let sorted = found.sorted { $0.bytes > $1.bytes }
            let total = sorted.reduce(Int64(0)) { $0 + $1.bytes }
            await MainActor.run { [weak self] in
                self?.cleanables = sorted
                self?.totalCleanableBytes = total
                self?.isScanningCleanables = false
            }
        }
    }

    func cleanArtifact(_ item: CleanableArtifact) -> TrashOutcome {
        let outcome = TrashService.trash(
            URL(fileURLWithPath: item.path),
            name: item.name,
            bytes: item.bytes,
            isDirectory: true,
            hasFullDiskAccess: true
        )
        if case .moved = outcome {
            cleanables.removeAll { $0.id == item.id }
            totalCleanableBytes = cleanables.reduce(0) { $0 + $1.bytes }
        }
        return outcome
    }
}

struct CleanableArtifact: Identifiable, Sendable {
    var id: String { path }
    let name: String
    let category: String
    let path: String
    let bytes: Int64
    let fileCount: Int
}
