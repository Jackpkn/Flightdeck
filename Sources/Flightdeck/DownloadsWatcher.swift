import AppKit
import CryptoKit
import Foundation

/// Coarse file grouping, used for filtering rather than coloring — the
/// extension badge already states the exact type, so a second color-coded
/// encoding of the same fact would be decoration.
enum FileCategory: String, CaseIterable, Sendable {
    case image, document, archive, installer, media, code, other

    var label: String {
        switch self {
        case .image:     return "IMAGES"
        case .document:  return "DOCS"
        case .archive:   return "ARCHIVES"
        case .installer: return "INSTALLERS"
        case .media:     return "MEDIA"
        case .code:      return "CODE"
        case .other:     return "OTHER"
        }
    }

    static func of(_ url: URL) -> FileCategory {
        of(extension: url.pathExtension.lowercased())
    }

    /// Path-string variant — the disk index classifies tens of thousands of
    /// files per pass and building a URL for each one is pure overhead.
    static func of(path: String) -> FileCategory {
        guard let dot = path.lastIndex(of: "."),
              let slash = path.lastIndex(of: "/"), dot > slash else { return .other }
        return of(extension: path[path.index(after: dot)...].lowercased())
    }

    static func of(extension ext: String) -> FileCategory {
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "bmp", "tiff":
            return .image
        case "pdf", "doc", "docx", "pages", "txt", "rtf", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "csv", "md":
            return .document
        case "zip", "tar", "gz", "tgz", "bz2", "7z", "rar", "xz":
            return .archive
        case "dmg", "pkg", "app", "installer":
            return .installer
        case "mp4", "mov", "avi", "mkv", "mp3", "wav", "m4a", "flac", "aac", "webm":
            return .media
        case "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "java", "kt", "c", "cpp", "h", "sh", "json", "yaml", "yml":
            return .code
        default:
            return .other
        }
    }
}

struct FileEntry: Identifiable, Sendable {
    let id: String // full path — stable across a rename since we replace the entry
    let url: URL
    let name: String
    let addedAt: Date
    let sizeBytes: Int64
    let lastAccessed: Date?
    let category: FileCategory
    var isDirectory = false

    /// Untouched for a month — the real signal for "you can probably bin this".
    var isStale: Bool {
        guard let lastAccessed else { return false }
        return lastAccessed.timeIntervalSinceNow < -30 * 24 * 3600
    }
}

/// Watches ~/Downloads with a DispatchSource on the directory's own file
/// descriptor — no Full Disk Access needed, this specific folder is readable
/// by any app by default, same as Finder showing it to you.
@Observable
final class DownloadsWatcher: FileRenaming {
    private(set) var files: [FileEntry] = []
    /// Paths that share identical content with another file, from the last scan.
    private(set) var duplicateIds: Set<String> = []
    private(set) var isScanningDuplicates = false
    private(set) var lastDuplicateScan: Date?

    private var knownPaths: Set<String> = []
    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1

    private var downloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    var staleCount: Int {
        files.filter(\.isStale).count
    }

    func start() {
        rescan(seedOnly: true)

        fd = Darwin.open(downloadsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.rescan(seedOnly: false) }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
        }
        src.resume()
        source = src
    }

    /// Re-reads the folder — used after an undo puts a file back, since the
    /// vnode watch fires for the directory but the list is rebuilt from scratch.
    func reload() {
        rescan(seedOnly: false)
    }

    private func rescan(seedOnly: Bool) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .contentAccessDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        if seedOnly {
            for url in items { knownPaths.insert(url.path) }
            files = items.compactMap(makeEntry).sorted { $0.addedAt > $1.addedAt }
            files = Array(files.prefix(30))
            return
        }

        for url in items where !knownPaths.contains(url.path) {
            knownPaths.insert(url.path)
            if let entry = makeEntry(url) {
                files.insert(entry, at: 0)
            }
        }
        if files.count > 100 {
            files.removeLast(files.count - 100)
        }
    }

    private func makeEntry(_ url: URL) -> FileEntry? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .contentAccessDateKey])
        return FileEntry(
            id: url.path,
            url: url,
            name: url.lastPathComponent,
            addedAt: values?.contentModificationDate ?? Date(),
            sizeBytes: Int64(values?.fileSize ?? 0),
            lastAccessed: values?.contentAccessDate,
            category: FileCategory.of(url)
        )
    }

    // MARK: - Duplicate detection

    /// Size-buckets first and only hashes files whose size collides — hashing
    /// every download on every scan would read the whole folder for nothing.
    /// Runs off the main thread and streams each file in 1 MB chunks so a large
    /// download never lands in memory whole.
    func findDuplicates() {
        guard !isScanningDuplicates else { return }
        isScanningDuplicates = true

        let candidates = files
        // The hashing runs on a detached task that captures only the Sendable
        // entry list; state is mutated back on the main actor.
        Task { @MainActor in
            let duplicates = await Self.scan(candidates)
            self.duplicateIds = duplicates
            self.isScanningDuplicates = false
            self.lastDuplicateScan = Date()
        }
    }

    private static func scan(_ candidates: [FileEntry]) async -> Set<String> {
        await Task.detached(priority: .utility) {
            var bySize: [Int64: [FileEntry]] = [:]
            for entry in candidates where entry.sizeBytes > 0 {
                bySize[entry.sizeBytes, default: []].append(entry)
            }

            var duplicates: Set<String> = []
            for (_, bucket) in bySize where bucket.count > 1 {
                var byHash: [String: [String]] = [:]
                for entry in bucket {
                    guard let hash = sha256(of: entry.url) else { continue }
                    byHash[hash, default: []].append(entry.id)
                }
                for (_, ids) in byHash where ids.count > 1 {
                    duplicates.formUnion(ids)
                }
            }
            return duplicates
        }.value
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Real file actions, not placeholders

    func reveal(_ entry: FileEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    func open(_ entry: FileEntry) {
        NSWorkspace.shared.open(entry.url)
    }

    func permission(for entry: FileEntry) -> FileGuard {
        FileGuard.evaluate(entry.url, hasFullDiskAccess: true)
    }

    @discardableResult
    func moveToTrash(_ entry: FileEntry) -> TrashOutcome {
        let outcome = TrashService.trash(
            entry.url,
            name: entry.name,
            bytes: entry.sizeBytes,
            isDirectory: entry.isDirectory,
            // Downloads is inside the home folder, so FDA is never the blocker
            // here — but a locked or read-only item still is.
            hasFullDiskAccess: true
        )
        if case .moved = outcome {
            files.removeAll { $0.id == entry.id }
            knownPaths.remove(entry.id)
            duplicateIds.remove(entry.id)
        }
        return outcome
    }

    func rename(_ entry: FileEntry, to newName: String) {
        guard !newName.isEmpty, newName != entry.name else { return }
        let newURL = entry.url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: entry.url, to: newURL)
            knownPaths.remove(entry.id)
            knownPaths.insert(newURL.path)
            if let idx = files.firstIndex(where: { $0.id == entry.id }) {
                files[idx] = FileEntry(
                    id: newURL.path,
                    url: newURL,
                    name: newName,
                    addedAt: entry.addedAt,
                    sizeBytes: entry.sizeBytes,
                    lastAccessed: entry.lastAccessed,
                    category: FileCategory.of(newURL)
                )
            }
        } catch {
            print("DownloadsWatcher: rename failed — \(error)")
        }
    }
}
