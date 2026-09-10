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

    private let queue = DispatchQueue(label: "com.flightdeck.duplicatescanner", qos: .userInitiated)

    public init() {}

    // MARK: - Computed Properties

    public var totalReclaimableDuplicateBytes: Int64 {
        duplicateSets.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var totalSelectedBytes: Int64 {
        var bytes: Int64 = 0
        let setMap = Dictionary(uniqueKeysWithValues: duplicateSets.flatMap { set in
            set.files.map { ($0.id, set.fileSize) }
        })
        for id in selectedFileIds {
            if let size = setMap[id] {
                bytes += size
            } else if let file = largeAndOldFiles.first(where: { $0.id == id }) {
                bytes += file.sizeBytes
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

    /// Scans standard user directories (~/Downloads, ~/Desktop) for duplicates and stale files.
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
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                    options: [.skipsPackageDescendants]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                          resourceValues.isRegularFile == true,
                          let fileSize = resourceValues.fileSize,
                          fileSize > 10_240 // skip < 10KB
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

            // Filter out unique file sizes (size collision is a prerequisite for duplicates)
            let candidateBuckets = sizeBuckets.filter { $0.value.count > 1 }
            let totalCandidates = candidateBuckets.values.reduce(0) { $0 + $1.count }
            var hashedCount = 0

            // PASS 2: Stream-hash candidate files in 1MB chunks using SHA-256
            var hashBuckets: [String: (fileSize: Int64, files: [ScannedFileItem])] = [:]

            for (_, candidates) in candidateBuckets {
                for candidate in candidates {
                    if let digest = Self.computeStreamingSHA256(for: candidate.url) {
                        hashBuckets[digest, default: (candidate.sizeBytes, [])].files.append(candidate)
                    }
                    hashedCount += 1
                    if totalCandidates > 0 {
                        let p = Double(hashedCount) / Double(totalCandidates)
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

            DispatchQueue.main.async {
                self.duplicateSets = duplicates
                self.largeAndOldFiles = largeOrOld
                self.isScanning = false
                self.scanProgress = 1.0
                // Auto-select duplicate candidates (keeping the oldest original copy)
                self.autoSelectDuplicates()
            }
        }
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
