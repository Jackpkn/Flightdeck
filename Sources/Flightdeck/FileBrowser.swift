import AppKit
import Foundation

/// Navigable, whole-filesystem browsing — the same `FileEntry` model the
/// downloads panel uses, just not pinned to one folder.
///
/// Reach is bounded by TCC, not by us: ~/Desktop, ~/Documents and ~/Downloads
/// prompt for per-folder consent, and anything beyond the home directory needs
/// Full Disk Access. FDA cannot be requested with a dialog (unlike
/// Accessibility) — it has to be toggled in System Settings, so this detects
/// whether it's on and can deep-link there.
@Observable
final class FileBrowser: FileRenaming {
    private(set) var currentURL: URL
    private(set) var entries: [FileEntry] = []
    private(set) var loadError: String?
    private(set) var hasFullDiskAccess = false
    private(set) var currentGitBranch: String?
    private(set) var volumeTotalBytes: Int64 = 0
    private(set) var volumeFreeBytes: Int64 = 0
    private(set) var volumeName: String = "Macintosh HD"

    var totalFilteredBytes: Int64 {
        filteredEntries.reduce(0) { $0 + $1.sizeBytes }
    }

    var volumeUsedBytes: Int64 {
        max(0, volumeTotalBytes - volumeFreeBytes)
    }

    var volumeUsageRatio: Double {
        volumeTotalBytes > 0 ? min(1.0, max(0.0, Double(volumeUsedBytes) / Double(volumeTotalBytes))) : 0.0
    }

    enum SortOrder: String, CaseIterable, Sendable {
        case name, size, modified

        var label: String {
            switch self {
            case .name:     return "NAME"
            case .size:     return "SIZE"
            case .modified: return "DATE"
            }
        }
    }

    var sortOrder: SortOrder = .modified {
        didSet { reload() }
    }
    var showHidden = false {
        didSet { reload() }
    }
    var searchQuery = ""
    var categoryFilter: FileCategory? = nil
    var onlyStale = false
    var onlyFolders = false
    var previewEntry: FileEntry? = nil

    var staleCount: Int {
        entries.filter { !$0.isDirectory && $0.isStale }.count
    }

    var filteredEntries: [FileEntry] {
        entries.filter { entry in
            if onlyFolders && !entry.isDirectory { return false }
            if onlyStale && !entry.isStale { return false }
            if let categoryFilter {
                if entry.isDirectory || entry.category != categoryFilter { return false }
            }
            if !searchQuery.isEmpty {
                let query = searchQuery.trimmingCharacters(in: .whitespaces)
                if !entry.name.localizedCaseInsensitiveContains(query) &&
                    !entry.url.pathExtension.localizedCaseInsensitiveContains(query) {
                    return false
                }
            }
            return true
        }
    }

    func copyPath(for entry: FileEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.url.path, forType: .string)
    }

    func copyCurrentPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentURL.path, forType: .string)
    }

    /// One-click destinations, all real directories on this machine.
    static let shortcuts: [(label: String, url: URL)] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("Home", home),
            ("Desktop", home.appendingPathComponent("Desktop")),
            ("Documents", home.appendingPathComponent("Documents")),
            ("Downloads", home.appendingPathComponent("Downloads")),
            ("Library", home.appendingPathComponent("Library")),
            ("Applications", URL(fileURLWithPath: "/Applications")),
            ("Root", URL(fileURLWithPath: "/")),
        ]
    }()

    init(start: URL? = nil) {
        currentURL = start ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func start() {
        hasFullDiskAccess = Self.detectFullDiskAccess()
        reload()
    }

    var breadcrumbs: [(name: String, url: URL)] {
        var parts: [(String, URL)] = []
        var url = currentURL
        while url.path != "/" {
            parts.append((url.lastPathComponent, url))
            url = url.deletingLastPathComponent()
        }
        parts.append(("/", URL(fileURLWithPath: "/")))
        return parts.reversed()
    }

    var canGoUp: Bool { currentURL.path != "/" }

    func navigate(to url: URL) {
        currentURL = url
        reload()
    }

    func goUp() {
        guard canGoUp else { return }
        navigate(to: currentURL.deletingLastPathComponent())
    }

    /// Enters directories; opens anything else with its default app.
    func activate(_ entry: FileEntry) {
        if entry.isDirectory {
            navigate(to: entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    func reload() {
        hasFullDiskAccess = Self.detectFullDiskAccess()
        updateVolumeInfo()
        detectGitBranch()
        do {
            var options: FileManager.DirectoryEnumerationOptions = []
            if !showHidden { options.insert(.skipsHiddenFiles) }

            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey, .fileSizeKey,
                    .contentAccessDateKey, .isDirectoryKey,
                ],
                options: options
            )
            entries = sorted(urls.compactMap(Self.makeEntry))
            loadError = nil
        } catch {
            entries = []
            loadError = (error as NSError).localizedDescription
        }
    }

    private func updateVolumeInfo() {
        if let values = try? currentURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeNameKey]) {
            volumeTotalBytes = Int64(values.volumeTotalCapacity ?? 0)
            volumeFreeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
            if let name = values.volumeName, !name.isEmpty {
                volumeName = name
            }
        } else if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: currentURL.path) {
            volumeTotalBytes = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            volumeFreeBytes = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
    }

    private func detectGitBranch() {
        var checkURL = currentURL
        while checkURL.path != "/" {
            let gitDir = checkURL.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    let headURL = gitDir.appendingPathComponent("HEAD")
                    if let headContent = try? String(contentsOf: headURL, encoding: .utf8) {
                        let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("ref: refs/heads/") {
                            currentGitBranch = String(trimmed.dropFirst("ref: refs/heads/".count))
                            return
                        } else if trimmed.count >= 7 {
                            currentGitBranch = String(trimmed.prefix(7))
                            return
                        }
                    }
                } else {
                    // .git file for worktree / submodules
                    if let gitFile = try? String(contentsOf: gitDir, encoding: .utf8),
                       gitFile.hasPrefix("gitdir: ") {
                        let relPath = gitFile.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
                        let targetURL = relPath.hasPrefix("/") ? URL(fileURLWithPath: relPath) : checkURL.appendingPathComponent(relPath)
                        let headURL = targetURL.appendingPathComponent("HEAD")
                        if let headContent = try? String(contentsOf: headURL, encoding: .utf8) {
                            let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.hasPrefix("ref: refs/heads/") {
                                currentGitBranch = String(trimmed.dropFirst("ref: refs/heads/".count))
                                return
                            }
                        }
                    }
                }
                break
            }
            checkURL = checkURL.deletingLastPathComponent()
        }
        currentGitBranch = nil
    }

    private func sorted(_ items: [FileEntry]) -> [FileEntry] {
        // Directories first — standard file-browser behavior, and it keeps
        // folders reachable when a directory holds thousands of files.
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sortOrder {
            case .name:     return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size:     return a.sizeBytes > b.sizeBytes
            case .modified: return a.addedAt > b.addedAt
            }
        }
    }

    private static func makeEntry(_ url: URL) -> FileEntry? {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey, .fileSizeKey, .contentAccessDateKey, .isDirectoryKey,
        ])
        return FileEntry(
            id: url.path,
            url: url,
            name: url.lastPathComponent,
            addedAt: values?.contentModificationDate ?? .distantPast,
            sizeBytes: Int64(values?.fileSize ?? 0),
            lastAccessed: values?.contentAccessDate,
            category: FileCategory.of(url),
            isDirectory: values?.isDirectory ?? false
        )
    }

    // MARK: - Full Disk Access

    /// Probes a path only readable with FDA. `isReadableFile` lies here, so
    /// this attempts an actual read.
    private static func detectFullDiskAccess() -> Bool {
        let probes = [
            NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        for path in probes {
            guard let handle = FileHandle(forReadingAtPath: path) else { continue }
            defer { try? handle.close() }
            if let data = try? handle.read(upToCount: 1), !data.isEmpty {
                return true
            }
        }
        return false
    }

    /// FDA has no programmatic prompt — the only honest move is to open the
    /// exact settings pane and let the user grant it.
    func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Actions

    func reveal(_ entry: FileEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    /// What can be done with a row, worked out before any button is drawn.
    func permission(for entry: FileEntry) -> FileGuard {
        FileGuard.evaluate(entry.url, hasFullDiskAccess: hasFullDiskAccess)
    }

    /// Whether the folder currently open is off-limits as a whole, so the panel
    /// can say so once at the top instead of on every single row.
    var currentFolderGuard: FileGuard {
        FileGuard.evaluate(currentURL, hasFullDiskAccess: hasFullDiskAccess)
    }

    @discardableResult
    func moveToTrash(_ entry: FileEntry) -> TrashOutcome {
        let outcome = TrashService.trash(
            entry.url,
            name: entry.name,
            bytes: entry.sizeBytes,
            isDirectory: entry.isDirectory,
            hasFullDiskAccess: hasFullDiskAccess
        )
        if case .moved = outcome {
            entries.removeAll { $0.id == entry.id }
        }
        return outcome
    }

    func rename(_ entry: FileEntry, to newName: String) {
        guard !newName.isEmpty, newName != entry.name else { return }
        let destination = entry.url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: entry.url, to: destination)
            reload()
        } catch {
            loadError = "Couldn't rename \(entry.name): \((error as NSError).localizedDescription)"
        }
    }
}
