import AppKit
import Foundation
import SwiftUI

/// Categorizes the user data directories associated with an application.
public enum LeftoverKind: String, CaseIterable, Sendable {
    case applicationSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case savedState = "Saved State"
    case containers = "Containers"
    case logs = "Logs"
    case other = "Other"

    public var icon: String {
        switch self {
        case .applicationSupport: return "folder.fill.badge.person.crop"
        case .caches: return "archivebox.fill"
        case .preferences: return "slider.horizontal.3"
        case .savedState: return "clock.arrow.circlepath"
        case .containers: return "cube.transparent.fill"
        case .logs: return "doc.text.fill"
        case .other: return "folder.fill"
        }
    }
}

/// A specific filesystem path holding user data for an application.
public struct RelatedPath: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let category: LeftoverKind
    public let sizeBytes: Int64

    public init(url: URL, category: LeftoverKind, sizeBytes: Int64) {
        self.url = url
        self.category = category
        self.sizeBytes = sizeBytes
    }
}

/// A discovered macOS application with its bundle metadata and complete storage footprint.
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { bundleURL.path }
    public let name: String
    public let bundleId: String
    public let version: String
    public let bundleURL: URL
    public let appBinarySize: Int64
    public let relatedPaths: [RelatedPath]
    public let totalSizeBytes: Int64
    public let isSystemApp: Bool

    public init(
        name: String,
        bundleId: String,
        version: String,
        bundleURL: URL,
        appBinarySize: Int64,
        relatedPaths: [RelatedPath],
        isSystemApp: Bool
    ) {
        self.name = name
        self.bundleId = bundleId
        self.version = version
        self.bundleURL = bundleURL
        self.appBinarySize = appBinarySize
        self.relatedPaths = relatedPaths
        self.totalSizeBytes = appBinarySize + relatedPaths.reduce(0) { $0 + $1.sizeBytes }
        self.isSystemApp = isSystemApp
    }

    public var userDataSize: Int64 {
        relatedPaths.filter { $0.category == .applicationSupport || $0.category == .containers }.reduce(0) { $0 + $1.sizeBytes }
    }

    public var cachesSize: Int64 {
        relatedPaths.filter { $0.category == .caches || $0.category == .savedState }.reduce(0) { $0 + $1.sizeBytes }
    }
}

/// Leftover storage left behind by an application that has already been deleted from /Applications.
public struct OrphanedAppLeftover: Identifiable, Hashable, Sendable {
    public var id: String { bundleId }
    public let inferredName: String
    public let bundleId: String
    public let paths: [RelatedPath]
    public let totalSizeBytes: Int64

    public init(inferredName: String, bundleId: String, paths: [RelatedPath]) {
        self.inferredName = inferredName
        self.bundleId = bundleId
        self.paths = paths
        self.totalSizeBytes = paths.reduce(0) { $0 + $1.sizeBytes }
    }
}

/// Deep application discovery and leftover tracer.
/// Discovers apps in /Applications and ~/Applications, calculates their full footprint
/// across ~/Library, finds orphaned leftovers from deleted apps, and safely uninstalls.
@Observable
public final class AppUninstaller {
    public static let shared = AppUninstaller()

    public private(set) var apps: [InstalledApp] = []
    public private(set) var orphanedLeftovers: [OrphanedAppLeftover] = []
    public private(set) var isScanning = false
    public private(set) var isUninstalling = false
    public var searchQuery: String = ""

    public enum SortOrder {
        case sizeDescending
        case nameAscending
    }
    public var sortOrder: SortOrder = .sizeDescending

    private let queue = DispatchQueue(label: "com.flightdeck.appuninstaller", qos: .utility)

    public init() {}

    public var filteredApps: [InstalledApp] {
        let result: [InstalledApp]
        if searchQuery.isEmpty {
            result = apps
        } else {
            let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
            result = apps.filter {
                $0.name.lowercased().contains(q) || $0.bundleId.lowercased().contains(q)
            }
        }

        switch sortOrder {
        case .sizeDescending:
            return result.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
        case .nameAscending:
            return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    public var totalReclaimableBytes: Int64 {
        apps.filter { !$0.isSystemApp }.reduce(0) { $0 + $1.totalSizeBytes }
    }

    public var totalOrphanedBytes: Int64 {
        orphanedLeftovers.reduce(0) { $0 + $1.totalSizeBytes }
    }

    // MARK: - Scanning

    public func scan() {
        guard !isScanning else { return }
        isScanning = true

        queue.async { [weak self] in
            guard let self else { return }
            let discoveredApps = Self.discoverInstalledApps()
            let knownBundleIds = Set(discoveredApps.map(\.bundleId))
            let orphans = Self.discoverOrphanedLeftovers(knownBundleIds: knownBundleIds)

            DispatchQueue.main.async {
                self.apps = discoveredApps
                self.orphanedLeftovers = orphans
                self.isScanning = false
            }
        }
    }

    public static func discoverInstalledApps() -> [InstalledApp] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        let searchDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]

        var apps: [InstalledApp] = []

        for dir in searchDirectories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isApplicationKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url) else { continue }
                let bundleId = bundle.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
                let displayName = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleVersion"] as? String)
                    ?? "1.0"

                let isSystem = url.path.hasPrefix("/System/") || FileGuard.isSystemProtected(url.path)
                let binarySize = DevCleaner.calculateDirectorySize(at: url)
                let related = isSystem ? [] : findRelatedPaths(bundleId: bundleId, appName: displayName, home: home)

                apps.append(InstalledApp(
                    name: displayName,
                    bundleId: bundleId,
                    version: version,
                    bundleURL: url,
                    appBinarySize: binarySize,
                    relatedPaths: related,
                    isSystemApp: isSystem
                ))
            }
        }

        return apps.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
    }

    /// Traces all support directories for a specific bundle ID in ~/Library.
    public static func findRelatedPaths(bundleId: String, appName: String, home: URL) -> [RelatedPath] {
        guard !bundleId.isEmpty else { return [] }
        let fm = FileManager.default
        var results: [RelatedPath] = []

        let targets: [(kind: LeftoverKind, path: URL)] = [
            (.applicationSupport, home.appendingPathComponent("Library/Application Support/\(bundleId)")),
            (.applicationSupport, home.appendingPathComponent("Library/Application Support/\(appName)")),
            (.caches, home.appendingPathComponent("Library/Caches/\(bundleId)")),
            (.preferences, home.appendingPathComponent("Library/Preferences/\(bundleId).plist")),
            (.savedState, home.appendingPathComponent("Library/Saved Application State/\(bundleId).savedState")),
            (.containers, home.appendingPathComponent("Library/Containers/\(bundleId)")),
            (.logs, home.appendingPathComponent("Library/Logs/\(appName)")),
            (.logs, home.appendingPathComponent("Library/Logs/\(bundleId)"))
        ]

        var seenPaths = Set<String>()

        for target in targets {
            let path = target.path.path
            guard !seenPaths.contains(path), fm.fileExists(atPath: path) else { continue }
            seenPaths.insert(path)

            var isDir: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDir)

            let size: Int64
            if isDir.boolValue {
                size = DevCleaner.calculateDirectorySize(at: target.path)
            } else {
                let attrs = try? fm.attributesOfItem(atPath: path)
                size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            }

            if size > 0 {
                results.append(RelatedPath(url: target.path, category: target.kind, sizeBytes: size))
            }
        }

        return results
    }

    /// Detects orphaned leftover folders in ~/Library/Application Support and Caches
    /// whose parent app no longer exists in /Applications or ~/Applications.
    public static func discoverOrphanedLeftovers(knownBundleIds: Set<String>) -> [OrphanedAppLeftover] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var leftoversByBundle: [String: (name: String, paths: [RelatedPath])] = [:]

        // 1. Scan Application Support for bundle-styled folders
        let appSupport = home.appendingPathComponent("Library/Application Support")
        if let items = try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in items {
                let name = item.lastPathComponent
                // Check if it looks like a reverse-DNS bundle id (contains a dot and not Apple internal)
                if name.contains(".") && !name.hasPrefix("com.apple.") {
                    if !knownBundleIds.contains(name) {
                        let size = DevCleaner.calculateDirectorySize(at: item)
                        if size > 1024 * 1024 { // at least 1 MB
                            let simpleName = name.components(separatedBy: ".").last?.capitalized ?? name
                            let rel = RelatedPath(url: item, category: .applicationSupport, sizeBytes: size)
                            leftoversByBundle[name, default: (simpleName, [])].paths.append(rel)
                        }
                    }
                }
            }
        }

        // 2. Scan Caches
        let caches = home.appendingPathComponent("Library/Caches")
        if let items = try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in items {
                let name = item.lastPathComponent
                if name.contains(".") && !name.hasPrefix("com.apple.") && !knownBundleIds.contains(name) {
                    let size = DevCleaner.calculateDirectorySize(at: item)
                    if size > 1024 * 1024 {
                        let simpleName = name.components(separatedBy: ".").last?.capitalized ?? name
                        let rel = RelatedPath(url: item, category: .caches, sizeBytes: size)
                        leftoversByBundle[name, default: (simpleName, [])].paths.append(rel)
                    }
                }
            }
        }

        return leftoversByBundle.map { bundleId, tuple in
            OrphanedAppLeftover(inferredName: tuple.name, bundleId: bundleId, paths: tuple.paths)
        }.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
    }

    // MARK: - Safe Deletion / Uninstallation

    /// Uninstalls an application bundle and recycles all its associated user data to macOS Trash.
    public func uninstall(app: InstalledApp) {
        guard !app.isSystemApp else { return }
        guard !isUninstalling else { return }
        isUninstalling = true
        CockpitAudio.playPing()

        queue.async { [weak self] in
            guard let self else { return }
            var allUrls = [app.bundleURL]
            allUrls.append(contentsOf: app.relatedPaths.map(\.url))

            // Check each URL with FileGuard before trashing
            let safeUrls = allUrls.filter { url in
                let verdict = FileGuard.evaluate(url, hasFullDiskAccess: true)
                return verdict == .allowed
            }

            if !safeUrls.isEmpty {
                // Non-destructive: recycle to Trash
                NSWorkspace.shared.recycle(safeUrls) { _, _ in }
            }

            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.apps.removeAll { $0.id == app.id }
                }
                self.isUninstalling = false
                CockpitAudio.playSuccess()
            }
        }
    }

    /// Purges an orphaned leftover directory from deleted apps.
    public func purgeOrphaned(leftover: OrphanedAppLeftover) {
        CockpitAudio.playPing()
        queue.async { [weak self] in
            guard let self else { return }
            let urls = leftover.paths.map(\.url).filter {
                FileGuard.evaluate($0, hasFullDiskAccess: true) == .allowed
            }
            if !urls.isEmpty {
                NSWorkspace.shared.recycle(urls) { _, _ in }
            }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.orphanedLeftovers.removeAll { $0.id == leftover.id }
                }
                CockpitAudio.playSuccess()
            }
        }
    }
}
