import Foundation
import SwiftUI

/// Represents a single cleanable developer cache category on macOS.
public struct CruftCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let path: URL
    public var sizeBytes: Int64
    public let isRAM: Bool

    public init(
        id: String,
        name: String,
        icon: String,
        path: URL,
        sizeBytes: Int64 = 0,
        isRAM: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.path = path
        self.sizeBytes = sizeBytes
        self.isRAM = isRAM
    }
}

/// Discovers, measures, and purges multi-gigabyte developer caches (Xcode DerivedData,
/// SPM, Node/NPM, Gradle, CocoaPods) and flushes inactive RAM.
@Observable
public final class DevCleaner {
    public static let shared = DevCleaner()

    public private(set) var categories: [CruftCategory] = []
    public private(set) var isScanning = false
    public private(set) var isPurging = false
    public private(set) var lastReclaimedBytes: Int64 = 0

    public var totalCruftBytes: Int64 {
        categories.filter { !$0.isRAM }.reduce(0) { $0 + $1.sizeBytes }
    }

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.flightdeck.devcleaner", qos: .utility)

    public init() {
        self.categories = Self.defaultTargets
    }

    deinit {
        stop()
    }

    public static var defaultTargets: [CruftCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser

        return [
            CruftCategory(
                id: "xcode_derived_data",
                name: "Xcode DerivedData",
                icon: "hammer.fill",
                path: home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
            ),
            CruftCategory(
                id: "npm_cache",
                name: "Node / NPM Cache",
                icon: "cube.box.fill",
                path: home.appendingPathComponent(".npm/_cacache")
            ),
            CruftCategory(
                id: "gradle_cache",
                name: "Gradle Build Cache",
                icon: "terminal.fill",
                path: home.appendingPathComponent(".gradle/caches")
            ),
            CruftCategory(
                id: "spm_cache",
                name: "Swift Package Cache",
                icon: "swift",
                path: home.appendingPathComponent("Library/Caches/org.swift.swiftpm")
            ),
            CruftCategory(
                id: "cocoapods_cache",
                name: "CocoaPods Cache",
                icon: "archivebox.fill",
                path: home.appendingPathComponent("Library/Caches/CocoaPods")
            ),
            CruftCategory(
                id: "simulator_cache",
                name: "CoreSimulator Cache",
                icon: "iphone.gen3",
                path: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches")
            ),
            CruftCategory(
                id: "yarn_cache",
                name: "Yarn Cache",
                icon: "shippingbox.fill",
                path: home.appendingPathComponent("Library/Caches/Yarn")
            ),
            CruftCategory(
                id: "homebrew_cache",
                name: "Homebrew Downloads",
                icon: "cup.and.saucer.fill",
                path: home.appendingPathComponent("Library/Caches/Homebrew")
            ),
            CruftCategory(
                id: "cargo_cache",
                name: "Rust / Cargo Cache",
                icon: "gearshape.2.fill",
                path: home.appendingPathComponent(".cargo/registry/cache")
            ),
            CruftCategory(
                id: "pip_cache",
                name: "Python / pip Cache",
                icon: "cube.fill",
                path: home.appendingPathComponent("Library/Caches/pip")
            ),
            CruftCategory(
                id: "pnpm_cache",
                name: "pnpm Store Cache",
                icon: "shippingbox.and.arrow.backward.fill",
                path: home.appendingPathComponent("Library/pnpm/store")
            )
        ]
    }

    public func start() {
        scan()
        timer?.invalidate()
        // Refresh every 15 seconds to avoid continuous disk thrashing
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Scanning Sizes

    public func scan() {
        guard !isScanning else { return }
        isScanning = true

        queue.async { [weak self] in
            guard let self else { return }
            var updated = Self.defaultTargets

            for i in 0..<updated.count {
                let cat = updated[i]
                if !cat.isRAM {
                    let size = Self.calculateDirectorySize(at: cat.path)
                    updated[i].sizeBytes = size
                }
            }

            DispatchQueue.main.async {
                self.categories = updated
                self.isScanning = false
            }
        }
    }

    public static func calculateDirectorySize(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
                continue
            }
            let bytes = values.totalFileAllocatedSize ?? values.fileSize ?? 0
            total += Int64(bytes)
        }
        return total
    }

    // MARK: - Safe Purging

    /// Purge a specific cache category safely (clearing files within, keeping directory root).
    public func purge(category: CruftCategory) {
        guard !isPurging else { return }
        isPurging = true
        CockpitAudio.playPing()

        let catPath = category.path
        let catId = category.id

        queue.async { [weak self] in
            guard let self else { return }
            let freed = Self.safelyEmptyDirectory(at: catPath)

            DispatchQueue.main.async {
                self.lastReclaimedBytes = freed
                if let idx = self.categories.firstIndex(where: { $0.id == catId }) {
                    self.categories[idx].sizeBytes = 0
                }
                self.isPurging = false
            }

            // Quick verify scan
            self.queue.asyncAfter(deadline: .now() + 0.6) {
                self.scan()
            }
        }
    }

    /// Purge all developer caches with accumulated files.
    public func purgeAll() {
        guard !isPurging else { return }
        isPurging = true
        CockpitAudio.playPing()

        let targets = categories.filter { $0.sizeBytes > 0 }

        queue.async { [weak self] in
            guard let self else { return }
            var totalFreed: Int64 = 0

            for cat in targets {
                totalFreed += Self.safelyEmptyDirectory(at: cat.path)
            }

            DispatchQueue.main.async {
                self.lastReclaimedBytes = totalFreed
                for i in 0..<self.categories.count {
                    self.categories[i].sizeBytes = 0
                }
                self.isPurging = false
            }

            self.queue.asyncAfter(deadline: .now() + 0.6) {
                self.scan()
            }
        }
    }

    /// Releases inactive memory pages.
    public func flushRAM() {
        CockpitAudio.playPing()
        queue.async {
            // macOS purge binary (requires no root on standard user sessions for inactive app caches)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
            try? task.run()
            task.waitUntilExit()
        }
    }

    // MARK: - Directory Safety

    public static func safelyEmptyDirectory(at url: URL) -> Int64 {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return 0 }

        // Extra guard: Path must be under current user's home and contain valid cache identifiers
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return 0 }
        let isSafeTarget = path.contains("DerivedData")
            || path.contains("cache")
            || path.contains("Cache")
            || path.contains("Caches")
            || path.contains("pnpm")
            || path.contains("CoreSimulator")
        guard isSafeTarget else { return 0 }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
        ) else {
            return 0
        }

        var freed: Int64 = 0
        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let size = isDir ? calculateDirectorySize(at: item) : Int64((try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            do {
                try FileManager.default.removeItem(at: item)
                freed += size
            } catch {
                // Skip files in active use
            }
        }
        return freed
    }

    /// Synchronously scans all default developer cache targets and measures their disk usage.
    public static func scanSynchronously() -> [CruftCategory] {
        var targets = defaultTargets
        for i in 0..<targets.count {
            if !targets[i].isRAM {
                targets[i].sizeBytes = calculateDirectorySize(at: targets[i].path)
            }
        }
        return targets
    }

    /// Synchronously empties non-RAM cache directories and returns total bytes reclaimed.
    @discardableResult
    public static func purgeSynchronously(categories: [CruftCategory]) -> Int64 {
        var totalFreed: Int64 = 0
        for cat in categories where !cat.isRAM {
            totalFreed += safelyEmptyDirectory(at: cat.path)
        }
        return totalFreed
    }
}
