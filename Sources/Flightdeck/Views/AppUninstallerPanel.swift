import SwiftUI
import AppKit

/// Cockpit-grade Application Uninstaller & Leftover Hunter.
/// Inspects macOS applications, visualizes their full footprint across ~/Library,
/// finds orphaned remnants from previously deleted apps, and executes non-destructive
/// recycling to macOS Trash with explicit confirmation.
struct AppUninstallerPanel: View {
    @Environment(AppUninstaller.self) private var uninstaller
    @FocusState private var searchFocused: Bool

    enum ViewMode: String, CaseIterable {
        case installedApps = "INSTALLED APPS"
        case orphanedLeftovers = "ORPHANED LEFTOVERS"
    }

    @State private var viewMode: ViewMode = .installedApps
    @State private var selectedAppId: String? = nil
    @State private var appToUninstall: InstalledApp? = nil
    @State private var leftoverToPurge: OrphanedAppLeftover? = nil
    @State private var confirmingPurgeAllOrphans = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            toolbar

            switch viewMode {
            case .installedApps:
                installedAppsContent
            case .orphanedLeftovers:
                orphansContent
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.accent)
        .cornerBracket(color: Theme.accent)
        .onAppear {
            if uninstaller.apps.isEmpty && !uninstaller.isScanning {
                uninstaller.scan()
            }
        }
        .confirmationDialog(
            "UNINSTALL APPLICATION",
            isPresented: Binding(
                get: { appToUninstall != nil },
                set: { if !$0 { appToUninstall = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let app = appToUninstall {
                Button("UNINSTALL & RECYCLE TO TRASH (\(Formatters.bytes(app.totalSizeBytes)))", role: .destructive) {
                    uninstaller.uninstall(app: app)
                    appToUninstall = nil
                }
                Button("Cancel", role: .cancel) {
                    appToUninstall = nil
                }
            }
        } message: {
            if let app = appToUninstall {
                Text("Are you sure you want to uninstall \(app.name)? This will safely move \(app.name).app and all \(app.relatedPaths.count) associated Library folders (\(Formatters.bytes(app.totalSizeBytes))) to macOS Trash.")
            }
        }
        .confirmationDialog(
            "PURGE ORPHANED LEFTOVERS",
            isPresented: Binding(
                get: { leftoverToPurge != nil },
                set: { if !$0 { leftoverToPurge = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let orphan = leftoverToPurge {
                Button("PURGE LEFTOVERS (\(Formatters.bytes(orphan.totalSizeBytes)))", role: .destructive) {
                    uninstaller.purgeOrphaned(leftover: orphan)
                    leftoverToPurge = nil
                }
                Button("Cancel", role: .cancel) {
                    leftoverToPurge = nil
                }
            }
        } message: {
            if let orphan = leftoverToPurge {
                Text("Safely move leftover data folders for \(orphan.inferredName) (\(orphan.bundleId)) to macOS Trash?")
            }
        }
        .confirmationDialog(
            "PURGE ALL ORPHANED LEFTOVERS",
            isPresented: $confirmingPurgeAllOrphans,
            titleVisibility: .visible
        ) {
            Button("PURGE ALL (\(Formatters.bytes(uninstaller.totalOrphanedBytes)))", role: .destructive) {
                for orphan in uninstaller.orphanedLeftovers {
                    uninstaller.purgeOrphaned(leftover: orphan)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Safely recycle all \(uninstaller.orphanedLeftovers.count) orphaned leftover folders to macOS Trash? This will reclaim \(Formatters.bytes(uninstaller.totalOrphanedBytes)).")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(color: Theme.accent)
            Text("APP DEEP UNINSTALLER & LEFTOVER HUNTER")
                .font(Theme.display(11))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)

            let count = uninstaller.apps.count
            Text("\(count) APPS")
                .font(Theme.mono(8.5, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.accent.opacity(0.15), in: Capsule())
                .foregroundStyle(Theme.accent)

            if uninstaller.totalReclaimableBytes > 0 {
                Text("\(Formatters.bytes(uninstaller.totalReclaimableBytes)) DETECTED")
                    .font(Theme.mono(8.5, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .foregroundStyle(Theme.ink2)
            }

            Spacer(minLength: 8)

            Button {
                uninstaller.scan()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(uninstaller.isScanning ? .degrees(360) : .zero)
                        .animation(uninstaller.isScanning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: uninstaller.isScanning)
                    Text(uninstaller.isScanning ? "SCANNING..." : "SCAN APPS")
                        .font(Theme.mono(9, weight: .bold))
                }
                .foregroundStyle(uninstaller.isScanning ? Theme.accent : Theme.ink2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(uninstaller.isScanning)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Segmented mode picker
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    modeButton(for: mode)
                }
            }
            .padding(2)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            if viewMode == .installedApps {
                // Search bar
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.ink3)

                    TextField("Filter apps...", text: Bindable(uninstaller).searchQuery)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink1)
                        .focused($searchFocused)
                        .frame(width: 120)

                    if !uninstaller.searchQuery.isEmpty {
                        Button {
                            uninstaller.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(searchFocused ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))

                // Sort toggle
                Button {
                    uninstaller.sortOrder = uninstaller.sortOrder == .sizeDescending ? .nameAscending : .sizeDescending
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: uninstaller.sortOrder == .sizeDescending ? "arrow.down.square" : "textformat")
                        Text(uninstaller.sortOrder == .sizeDescending ? "SIZE" : "NAME")
                            .font(Theme.mono(9, weight: .bold))
                    }
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            } else if !uninstaller.orphanedLeftovers.isEmpty {
                Button {
                    confirmingPurgeAllOrphans = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                        Text("PURGE ALL ORPHANS (\(Formatters.bytes(uninstaller.totalOrphanedBytes)))")
                            .font(Theme.mono(9, weight: .bold))
                    }
                    .foregroundStyle(Theme.warn)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.warn.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Installed Apps Content

    private var installedAppsContent: some View {
        let items = uninstaller.filteredApps
        let activeApp = items.first(where: { $0.id == selectedAppId }) ?? items.first

        return Group {
            if items.isEmpty {
                if uninstaller.isScanning {
                    scanningEmptyState
                } else {
                    emptyState(title: "NO APPLICATIONS FOUND", subtitle: "Try adjusting your search query.")
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    // App List (Left)
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(items) { app in
                                appListRow(app: app, isSelected: activeApp?.id == app.id)
                            }
                        }
                    }
                    .frame(width: 320)
                    .scrollIndicators(.hidden)

                    // App Inspector / Telemetry (Right)
                    if let app = activeApp {
                        appDetailPane(app: app)
                    } else {
                        Spacer()
                    }
                }
            }
        }
    }

    private func appListRow(app: InstalledApp, isSelected: Bool) -> some View {
        Button {
            selectedAppId = app.id
        } label: {
            HStack(spacing: 10) {
                // App Icon
                appIcon(for: app.bundleURL.path, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(isSelected ? Theme.accent : Theme.ink1)
                            .lineLimit(1)

                        if app.isSystemApp {
                            Text("SYS")
                                .font(Theme.mono(7.5, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.white.opacity(0.08), in: Capsule())
                                .foregroundStyle(Theme.ink3)
                        }
                    }

                    Text("v\(app.version) · \(app.bundleId)")
                        .font(Theme.mono(8.5))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.bytes(app.totalSizeBytes))
                        .font(Theme.mono(10.5, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.ink2)

                    if !app.relatedPaths.isEmpty {
                        Text("+\(app.relatedPaths.count) items")
                            .font(Theme.mono(8))
                            .foregroundStyle(Theme.ink3)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.accent.opacity(0.12) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - App Detail Telemetry Pane

    private func appDetailPane(app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // App Banner
            HStack(spacing: 14) {
                appIcon(for: app.bundleURL.path, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(app.name)
                            .font(Theme.display(16))
                            .foregroundStyle(Theme.ink1)

                        if app.isSystemApp {
                            Text("SYSTEM PROTECTED")
                                .font(Theme.mono(8.5, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.white.opacity(0.08), in: Capsule())
                                .foregroundStyle(Theme.ink3)
                        }
                    }

                    Text("\(app.bundleId) · Version \(app.version)")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.ink3)

                    Text(app.bundleURL.path)
                        .font(Theme.mono(8.5))
                        .foregroundStyle(Theme.ink3.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([app.bundleURL])
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text("REVEAL")
                            .font(Theme.mono(9, weight: .bold))
                    }
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Reveal app in Finder")
            }
            .padding(14)
            .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))

            // Storage Breakdown Cards
            HStack(spacing: 10) {
                telemetryMetricCard(
                    title: "APP BINARY",
                    value: Formatters.bytes(app.appBinarySize),
                    icon: "app.dashed",
                    tint: Theme.accent
                )
                telemetryMetricCard(
                    title: "USER DATA",
                    value: Formatters.bytes(app.userDataSize),
                    icon: "folder.fill.badge.person.crop",
                    tint: Theme.violet
                )
                telemetryMetricCard(
                    title: "CACHES & STATE",
                    value: Formatters.bytes(app.cachesSize),
                    icon: "archivebox.fill",
                    tint: Theme.amber
                )
                telemetryMetricCard(
                    title: "TOTAL FOOTPRINT",
                    value: Formatters.bytes(app.totalSizeBytes),
                    icon: "chart.bar.fill",
                    tint: Theme.ink1
                )
            }

            // Related Library Paths Breakdown
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ASSOCIATED STORAGE PATHS (\(app.relatedPaths.count + 1))")
                        .font(Theme.mono(9.5, weight: .bold))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    Text("Recycled cleanly on uninstall")
                        .font(Theme.mono(8.5))
                        .foregroundStyle(Theme.ink3.opacity(0.7))
                }

                ScrollView {
                    VStack(spacing: 4) {
                        // Main Application Bundle
                        pathRow(
                            icon: "app.fill",
                            kind: "Application Bundle",
                            path: app.bundleURL.path,
                            size: app.appBinarySize,
                            isBinary: true
                        )

                        // Discovered Library Paths
                        ForEach(app.relatedPaths) { item in
                            pathRow(
                                icon: item.category.icon,
                                kind: item.category.rawValue,
                                path: item.url.path,
                                size: item.sizeBytes,
                                isBinary: false
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
                .scrollIndicators(.hidden)
            }

            Spacer(minLength: 0)

            // Uninstallation Action Footer
            HStack {
                if app.isSystemApp {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Theme.ink3)
                        Text("System applications are protected by macOS System Integrity Protection and cannot be uninstalled.")
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.ink3)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(Theme.accent)
                        Text("Files will be recycled to macOS Trash with FileGuard integrity validation.")
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.ink3)
                    }

                    Spacer()

                    Button {
                        appToUninstall = app
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                            Text("UNINSTALL & WIPE LEFTOVERS (\(Formatters.bytes(app.totalSizeBytes)))")
                                .font(Theme.mono(10, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.warn.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.warn, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(uninstaller.isUninstalling)
                }
            }
            .padding(12)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .glassPanel(accent: Theme.accent)
        .cornerBracket(color: Theme.accent)
    }

    private func telemetryMetricCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(tint)
                Text(title)
                    .font(Theme.mono(8, weight: .bold))
                    .foregroundStyle(Theme.ink3)
            }
            Text(value)
                .font(Theme.mono(12, weight: .bold))
                .foregroundStyle(Theme.ink1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }

    private func pathRow(icon: String, kind: String, path: String, size: Int64, isBinary: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(isBinary ? Theme.accent : Theme.ink2)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(kind)
                    .font(Theme.mono(8.5, weight: .bold))
                    .foregroundStyle(isBinary ? Theme.accent : Theme.ink2)

                Text(path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(Formatters.bytes(size))
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(Theme.ink2)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.white.opacity(0.015), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Orphaned Leftovers Content

    private var orphansContent: some View {
        let items = uninstaller.orphanedLeftovers

        return Group {
            if items.isEmpty {
                emptyState(
                    title: "NO ORPHANED LEFTOVERS DETECTED",
                    subtitle: "All detected ~/Library support directories correspond to currently installed apps."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { orphan in
                            orphanRow(orphan: orphan)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func orphanRow(orphan: OrphanedAppLeftover) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.warn.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "archivebox.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.warn)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(orphan.inferredName)
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.ink1)

                    Text(orphan.bundleId)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.ink3)
                }

                Text("\(orphan.paths.count) leftover folders across Application Support & Caches")
                    .font(Theme.mono(8.5))
                    .foregroundStyle(Theme.ink3)
            }

            Spacer()

            Text(Formatters.bytes(orphan.totalSizeBytes))
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.warn)

            Button {
                leftoverToPurge = orphan
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash.fill")
                    Text("PURGE")
                        .font(Theme.mono(9, weight: .bold))
                }
                .foregroundStyle(Theme.warn)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.warn.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: - Helper Views

    private func appIcon(for path: String, size: CGFloat) -> some View {
        let icon = NSWorkspace.shared.icon(forFile: path)
        return Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private var scanningEmptyState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("SCANNING MACOS APPLICATIONS & ~/LIBRARY CRUFT...")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text(title)
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.ink1)
            Text(subtitle)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func modeButton(for mode: ViewMode) -> some View {
        let isSelected = viewMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewMode = mode
            }
        } label: {
            HStack(spacing: 6) {
                Text(mode.rawValue)
                    .font(Theme.mono(9.5, weight: .bold))

                if mode == .orphanedLeftovers {
                    let count = uninstaller.orphanedLeftovers.count
                    if count > 0 {
                        Text("\(count)")
                            .font(Theme.mono(8, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.warn.opacity(0.2), in: Capsule())
                            .foregroundStyle(Theme.warn)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Theme.accent.opacity(0.18) : Color.white.opacity(0.03))
            .foregroundStyle(isSelected ? Theme.accent : Theme.ink3)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
