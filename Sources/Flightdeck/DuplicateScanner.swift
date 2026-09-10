import AppKit
import CryptoKit
import Foundation
import SwiftUI

/// Categorizes discovered files by media/utility format.
public enum DuplicateMediaKind: String, CaseIterable, Sendable {
    case archives = "Archives"
    case diskImages = "Disk Images & Installers"
    case media = "Media & Audio/Video"
    case documents = "Documents & PDFs"
    case codeAndOther = "Code & Other"

    public var icon: String {
        switch self {
        case .archives: return "archivebox.fill"
        case .diskImages: return "opticaldisc.fill"
        case .media: return "film.fill"
        case .documents: return "doc.text.fill"
        case .codeAndOther: return "curlybraces"
        }
    }

    public static func categorize(url: URL) -> DuplicateMediaKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar":
            return .archives
        case "dmg", "iso", "pkg", "app":
            return .diskImages
        case "mov", "mp4", "mkv", "avi", "webm", "mp3", "wav", "m4a", "flac", "png", "jpg", "jpeg", "gif", "webp", "heic":
            return .media
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "txt", "rtf", "pages", "numbers", "keynote":
            return .documents
        default:
            return .codeAndOther
        }
    }
}

/// An individual file entry identified in duplicate or stale sweeps.
public struct ScannedFileItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let sizeBytes: Int64
    public let modificationDate: Date
    public let category: DuplicateMediaKind

    public init(url: URL, sizeBytes: Int64, modificationDate: Date) {
        self.url = url
        self.name = url.lastPathComponent
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.category = DuplicateMediaKind.categorize(url: url)
    }

    public var ageInDays: Int {
        let seconds = Date().timeIntervalSince(modificationDate)
        return max(0, Int(seconds / 86400.0))
    }
}

/// A cluster of identical files sharing the exact SHA-256 byte digest.
public struct DuplicateSet: Identifiable, Hashable, Sendable {
    public var id: String { hash }
    public let hash: String
    public let fileSize: Int64
    public var files: [ScannedFileItem]

    public init(hash: String, fileSize: Int64, files: [ScannedFileItem]) {
        self.hash = hash
        self.fileSize = fileSize
        self.files = files
    }

    /// Bytes that can be reclaimed by removing all duplicates while keeping 1 original.
    public var reclaimableBytes: Int64 {
        guard files.count > 1 else { return 0 }
        return Int64(files.count - 1) * fileSize
    }
}

/// High-performance duplicate file and stale downloads scanner.
/// Employs a 2-pass algorithm (Size bucketing + chunked streaming SHA-256 hashing)
/// to detect exact clones across target folders without RAM bloat.
@Observable
public final class DuplicateScanner {
    public static let shared = DuplicateScanner()

    public private(set) var duplicateSets: [DuplicateSet] = []
    public private(set) var largeAndOldFiles: [ScannedFileItem] = []
    public private(set) var isScanning = false
    public private(set) var scanProgress: Double = 0.0
    public private(set) var currentScanningFolder: String = ""

    /// Selected target paths for duplicate cleanup.
    public var selectedFileIds: Set<String> = []

    /// Search/filter parameters
    public var searchQuery: String = ""
    public var selectedCategory: DuplicateMediaKind? = nil

    /// Cached file sizes to avoid expensive dictionary rebuilds on render frames.
    private var fileSizeLookup: [String: Int64] = [:]

    public static let ignoredFolderNames: Set<String> = [
        "node_modules", ".venv", "venv", "env", "__pycache__",
        ".pytest_cache", ".build", "build", "dist", "Pods", "Caches",
        ".gradle", ".cargo", "DerivedData", ".claude", ".gemini",
        "Library", ".Trash", ".localized", ".git", ".svn", ".hg"
    ]

    private let queue = DispatchQueue(label: "com.flightdeck.duplicatescanner", qos: .utility)

    public init() {}

    // MARK: - Computed Properties

    public var totalReclaimableDuplicateBytes: Int64 {
        duplicateSets.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var totalSelectedBytes: Int64 {
        var bytes: Int64 = 0
        for id in selectedFileIds {
            if let size = fileSizeLookup[id] {
                bytes += size
            }
        }
        return bytes
    }

    public var filteredDuplicateSets: [DuplicateSet] {
        var sets = duplicateSets
        if let cat = selectedCategory {
            sets = sets.filter { set in
                set.files.contains { $0.category == cat }
            }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
            sets = sets.filter { set in
                set.files.contains { $0.name.lowercased().contains(q) || $0.url.path.lowercased().contains(q) }
            }
        }
        return sets.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    public var filteredLargeAndOld: [ScannedFileItem] {
        var items = largeAndOldFiles
        if let cat = selectedCategory {
            items = items.filter { $0.category == cat }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
            items = items.filter { $0.name.lowercased().contains(q) }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Scanning Engine

    /// Scans standard user directories (~/Downloads, ~/Desktop) with depth limiting and smart folder pruning.
    public func scan(directories: [URL]? = nil) {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let targetDirs = directories ?? [
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true)
        ]

        queue.async { [weak self] in
            guard let self else { return }

            var collectedFiles: [ScannedFileItem] = []
            var largeOrOld: [ScannedFileItem] = []

            for dir in targetDirs {
                guard fm.fileExists(atPath: dir.path) else { continue }
                DispatchQueue.main.async {
                    self.currentScanningFolder = dir.lastPathComponent
                }

                guard let enumerator = fm.enumerator(
                    at: dir,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isDirectoryKey],
                    options: [.skipsPackageDescendants, .skipsHiddenFiles]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    let filename = fileURL.lastPathComponent

                    // 1. Skip blacklisted developer directories and hidden paths
                    if filename.hasPrefix(".") || Self.ignoredFolderNames.contains(filename) {
                        enumerator.skipDescendants()
                        continue
                    }

                    // 2. Skip application bundles or packages within downloads
                    let ext = fileURL.pathExtension.lowercased()
                    if ext == "app" || ext == "framework" || ext == "bundle" || ext == "download" || ext == "crdownload" || ext == "part" {
                        enumerator.skipDescendants()
                        continue
                    }

                    // 3. Limit depth to 3 levels below root target
                    let depth = fileURL.pathComponents.count - dir.pathComponents.count
                    if depth > 3 {
                        enumerator.skipDescendants()
                        continue
                    }

                    guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isDirectoryKey]) else {
                        continue
                    }

                    if resourceValues.isDirectory == true {
                        continue
                    }

                    guard resourceValues.isRegularFile == true,
                          let fileSize = resourceValues.fileSize,
                          fileSize >= 50 * 1024 // skip < 50KB to ignore tiny temporary files
                    else { continue }

                    let modDate = resourceValues.contentModificationDate ?? Date()
                    let item = ScannedFileItem(url: fileURL, sizeBytes: Int64(fileSize), modificationDate: modDate)
                    collectedFiles.append(item)

                    // Large (>250MB) or Old (>90 days)
                    if fileSize > 250 * 1024 * 1024 || item.ageInDays > 90 {
                        largeOrOld.append(item)
                    }
                }
            }

            // PASS 1: Bucket files by exact file size in bytes
            var sizeBuckets: [Int64: [ScannedFileItem]] = [:]
            for file in collectedFiles {
                sizeBuckets[file.sizeBytes, default: []].append(file)
            }

            // Filter out unique file sizes (size collision is prerequisite for duplicate)
            let candidateBuckets = sizeBuckets.filter { $0.value.count > 1 }
            let totalCandidates = candidateBuckets.values.reduce(0) { $0 + $1.count }
            var processedCandidates = 0
            var lastUpdate = Date()

            // PASS 2: 16KB Header Hash Pre-Filter
            // Groups candidate files by (size, headerHash) before doing full file hash.
            var headerBuckets: [String: [ScannedFileItem]] = [:]

            for (size, candidates) in candidateBuckets {
                for candidate in candidates {
                    if let headerHash = Self.computeHeaderSHA256(for: candidate.url) {
                        let key = "\(size)_\(headerHash)"
                        headerBuckets[key, default: []].append(candidate)
                    }
                    processedCandidates += 1
                    if Date().timeIntervalSince(lastUpdate) > 0.15 {
                        lastUpdate = Date()
                        let p = totalCandidates > 0 ? (Double(processedCandidates) / Double(totalCandidates) * 0.5) : 0.5
                        DispatchQueue.main.async {
                            self.scanProgress = p
                        }
                    }
                }
            }

            // PASS 3: Full Stream-Hash only for items with matching size AND matching 16KB header
            let fullCandidates = headerBuckets.filter { $0.value.count > 1 }
            var hashBuckets: [String: (fileSize: Int64, files: [ScannedFileItem])] = [:]
            let totalFullCandidates = fullCandidates.values.reduce(0) { $0 + $1.count }
            var fullProcessed = 0

            for (_, candidates) in fullCandidates {
                for candidate in candidates {
                    if let digest = Self.computeStreamingSHA256(for: candidate.url) {
                        hashBuckets[digest, default: (candidate.sizeBytes, [])].files.append(candidate)
                    }
                    fullProcessed += 1
                    if Date().timeIntervalSince(lastUpdate) > 0.15 {
                        lastUpdate = Date()
                        let p = 0.5 + (totalFullCandidates > 0 ? (Double(fullProcessed) / Double(totalFullCandidates) * 0.5) : 0.5)
                        DispatchQueue.main.async {
                            self.scanProgress = p
                        }
                    }
                }
            }

            // Keep only clusters with >= 2 identical files
            let duplicates = hashBuckets.compactMap { hash, tuple -> DuplicateSet? in
                guard tuple.files.count > 1 else { return nil }
                // Sort by date ascending: oldest file is original, newer are duplicates
                let sortedFiles = tuple.files.sorted { $0.modificationDate < $1.modificationDate }
                return DuplicateSet(hash: hash, fileSize: tuple.fileSize, files: sortedFiles)
            }.sorted { $0.reclaimableBytes > $1.reclaimableBytes }

            // Build fast size lookup map
            var lookup: [String: Int64] = [:]
            for set in duplicates {
                for f in set.files {
                    lookup[f.id] = set.fileSize
                }
            }
            for item in largeOrOld {
                lookup[item.id] = item.sizeBytes
            }

            DispatchQueue.main.async {
                self.fileSizeLookup = lookup
                self.duplicateSets = duplicates
                self.largeAndOldFiles = largeOrOld
                self.isScanning = false
                self.scanProgress = 1.0
                // Auto-select duplicate candidates (keeping the oldest original copy)
                self.autoSelectDuplicates()
            }
        }
    }

    /// Reads at most 16KB from the start of the file for lightning-fast pre-filtering.
    public static func computeHeaderSHA256(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let headerData = handle.readData(ofLength: 16 * 1024)
        guard !headerData.isEmpty else { return nil }
        let digest = SHA256.hash(data: headerData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes SHA-256 digest by reading file in 1MB chunks to prevent memory overhead.
    public static func computeStreamingSHA256(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB buffer

        while true {
            let data = handle.readData(ofLength: bufferSize)
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Auto-Select & Selection Actions

    /// Auto-selects redundant copies (keeps the oldest original file, selects all duplicates).
    public func autoSelectDuplicates() {
        var toSelect = Set<String>()
        for set in duplicateSets {
            // Index 0 is the original/oldest, dropFirst selects the extra copies
            for duplicate in set.files.dropFirst() {
                toSelect.insert(duplicate.id)
            }
        }
        self.selectedFileIds = toSelect
    }

    public func deselectAll() {
        self.selectedFileIds.removeAll()
    }

    public func toggleSelection(for fileId: String) {
        if selectedFileIds.contains(fileId) {
            selectedFileIds.remove(fileId)
        } else {
            selectedFileIds.insert(fileId)
        }
    }

    // MARK: - Safe Recycling

    /// Recycles all selected files to macOS Trash with FileGuard integrity validation.
    public func trashSelected(completion: @escaping (Int64) -> Void) {
        guard !selectedFileIds.isEmpty else { return }
        CockpitAudio.playPing()

        let idsToTrash = selectedFileIds
        queue.async { [weak self] in
            guard let self else { return }

            var urlsToTrash: [URL] = []
            var bytesReclaimed: Int64 = 0

            for id in idsToTrash {
                let url = URL(fileURLWithPath: id)
                // Guard check
                if FileGuard.evaluate(url, hasFullDiskAccess: true) == .allowed {
                    urlsToTrash.append(url)
                    let attrs = try? FileManager.default.attributesOfItem(atPath: id)
                    bytesReclaimed += (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                }
            }

            if !urlsToTrash.isEmpty {
                NSWorkspace.shared.recycle(urlsToTrash) { _, _ in }
            }

            DispatchQueue.main.async {
                // Remove trashed files from duplicateSets
                var updatedSets: [DuplicateSet] = []
                for var set in self.duplicateSets {
                    set.files.removeAll { idsToTrash.contains($0.id) }
                    if set.files.count > 1 {
                        updatedSets.append(set)
                    }
                }
                self.duplicateSets = updatedSets
                self.largeAndOldFiles.removeAll { idsToTrash.contains($0.id) }
                self.selectedFileIds.subtract(idsToTrash)

                CockpitAudio.playSuccess()
                completion(bytesReclaimed)
            }
        }
    }
}
