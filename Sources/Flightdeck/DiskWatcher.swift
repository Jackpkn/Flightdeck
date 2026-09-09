import Foundation
import CoreServices

/// Directories to re-read, plus subtrees the kernel told us it couldn't
/// describe precisely.
struct DiskChangeBatch: Sendable {
    var dirs: Set<String> = []
    /// Coalesced beyond recognition, or events were dropped — these need a real
    /// walk. Bounded to the affected subtree, not the whole disk.
    var subtrees: Set<String> = []
    var lastEventId: UInt64 = 0
    var replayed = false

    var isEmpty: Bool { dirs.isEmpty && subtrees.isEmpty }

    mutating func merge(_ other: DiskChangeBatch) {
        dirs.formUnion(other.dirs)
        subtrees.formUnion(other.subtrees)
        lastEventId = max(lastEventId, other.lastEventId)
        replayed = replayed || other.replayed
    }
}

/// FSEvents, wrapped. Two properties make it the only real option here, and
/// neither is available from the per-descriptor `DispatchSource` watch we use
/// on a single folder:
///
/// 1. It reports changes anywhere beneath a root without opening a descriptor
///    per directory — watching a whole home folder costs one stream.
/// 2. It can **replay history**. Persist the last event id, pass it as
///    `sinceWhen` next launch, and the kernel hands back everything that
///    happened while the app was closed. That is what makes "whatever gets
///    added or deleted is still tracked" true across restarts.
///
/// FSEvents reports *which paths changed*, never what changed about them — so
/// the caller re-reads those directories and diffs against its own cache.
final class DiskWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.flightdeck.fsevents", qos: .utility)
    private var handler: ((DiskChangeBatch) -> Void)?
    private(set) var watchedRoot: String?

    /// Older than this and the volume's event database may have rolled over,
    /// so a replay would silently miss changes. A cold walk is the honest move.
    private static let replayHorizon: TimeInterval = 7 * 24 * 3600

    var isRunning: Bool { stream != nil }

    /// The last event we processed for a root, and when — persisted so the next
    /// launch can resume instead of rescanning.
    private static func storedCursor(for root: String) -> (id: UInt64, at: Date)? {
        let defaults = UserDefaults.standard
        let id = defaults.object(forKey: idKey(root)) as? NSNumber
        let at = defaults.object(forKey: dateKey(root)) as? Date
        guard let id, let at else { return nil }
        return (id.uint64Value, at)
    }

    static func saveCursor(_ id: UInt64, for root: String) {
        guard id > 0 else { return }
        UserDefaults.standard.set(NSNumber(value: id), forKey: idKey(root))
        UserDefaults.standard.set(Date(), forKey: dateKey(root))
    }

    static func clearCursor(for root: String) {
        UserDefaults.standard.removeObject(forKey: idKey(root))
        UserDefaults.standard.removeObject(forKey: dateKey(root))
    }

    /// Whether a cached index for this root can be resumed by replaying events,
    /// or whether it has to be rebuilt from a walk.
    static func canReplay(root: String) -> Bool {
        guard let cursor = storedCursor(for: root) else { return false }
        return Date().timeIntervalSince(cursor.at) < replayHorizon
    }

    private static func idKey(_ root: String) -> String { "fsevents.id.\(root)" }
    private static func dateKey(_ root: String) -> String { "fsevents.at.\(root)" }

    // MARK: - Lifecycle

    /// - Parameter replayingHistory: resume from the persisted cursor and report
    ///   everything missed while we weren't running. `false` starts from now,
    ///   which is what you want right after a full walk.
    func start(root: String, replayingHistory: Bool, onChange: @escaping (DiskChangeBatch) -> Void) {
        stop()
        handler = onChange
        watchedRoot = root

        let since: FSEventStreamEventId
        if replayingHistory, let cursor = Self.storedCursor(for: root),
           Date().timeIntervalSince(cursor.at) < Self.replayHorizon {
            since = cursor.id
        } else {
            since = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            eventCallback,
            &context,
            [root] as CFArray,
            since,
            // The kernel coalesces within this window; our own debounce sits on
            // top of it, so this only has to stop the truly chatty bursts.
            0.4,
            flags
        ) else { return }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        guard let stream else { return }
        if let root = watchedRoot {
            Self.saveCursor(FSEventStreamGetLatestEventId(stream), for: root)
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        handler = nil
    }

    deinit { stop() }

    fileprivate func deliver(_ batch: DiskChangeBatch) {
        guard !batch.isEmpty || batch.replayed else { return }
        if let root = watchedRoot { Self.saveCursor(batch.lastEventId, for: root) }
        handler?(batch)
    }

    fileprivate var root: String? { watchedRoot }
}

/// A C function pointer, so it can't capture — the watcher rides along in
/// `clientCallBackInfo` and is recovered here.
private let eventCallback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, eventIds in
    guard let info else { return }
    let watcher = Unmanaged<DiskWatcher>.fromOpaque(info).takeUnretainedValue()
    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

    var batch = DiskChangeBatch()

    for index in 0..<min(count, paths.count) {
        let path = paths[index]
        let flags = eventFlags[index]
        batch.lastEventId = max(batch.lastEventId, eventIds[index])

        func has(_ flag: Int) -> Bool { flags & FSEventStreamEventFlags(flag) != 0 }

        if has(kFSEventStreamEventFlagHistoryDone) {
            batch.replayed = true
            continue
        }

        // The kernel is telling us it lost precision. Only a walk of this
        // subtree can restore the truth — but it's still one subtree, not the
        // whole disk.
        if has(kFSEventStreamEventFlagMustScanSubDirs)
            || has(kFSEventStreamEventFlagUserDropped)
            || has(kFSEventStreamEventFlagKernelDropped) {
            batch.subtrees.insert(path)
            continue
        }

        // The root itself moved or was replaced; nothing cached still applies.
        if has(kFSEventStreamEventFlagRootChanged) {
            batch.subtrees.insert(watcher.root ?? path)
            continue
        }

        if has(kFSEventStreamEventFlagItemIsDir) {
            // Both: the directory's own contents may have changed, and its
            // parent's list of subdirectories may have gained or lost it.
            batch.dirs.insert(path)
            if let parent = DiskIndex.parent(of: path) { batch.dirs.insert(parent) }
        } else if let parent = DiskIndex.parent(of: path) {
            batch.dirs.insert(parent)
        }
    }

    watcher.deliver(batch)
}
