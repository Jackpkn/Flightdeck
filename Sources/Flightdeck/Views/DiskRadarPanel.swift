import SwiftUI

/// "What's eating this folder" — total usage plus the biggest individual files
/// anywhere beneath it, each actionable.
struct DiskRadarPanel: View {
    @Environment(DiskScanner.self) private var scanner
    @Environment(FileBrowser.self) private var browser
    @Environment(ActionCenter.self) private var actions

    enum Lens: String, CaseIterable {
        case largest = "LARGEST"
        case caches = "CLEANABLE"
    }

    @State private var lens: Lens = .largest
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LiveDot(color: Theme.warning)
                Text("DISK RADAR").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)
                Spacer()
                scanButton
            }

            Text(browser.currentURL.path)
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.ink3.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)

            if scanner.result.filesScanned > 0 && !scanner.isScanning {
                trackingStrip
            }

            if scanner.isScanning {
                scanningState
            } else if scanner.result.filesScanned > 0 || !scanner.cleanables.isEmpty {
                resultsState
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan this folder to see total usage and its largest files.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.ink3)
                    Button {
                        scanner.scanCleanables()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("SCAN DEV CACHES")
                                .font(Theme.mono(9.5, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accentSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.accentSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(accent: Theme.warning)
        .cornerBracket(color: Theme.warning)
    }

    /// Says out loud whether these numbers are being maintained or are a
    /// frozen snapshot — and what the last update cost, which is the whole
    /// argument for tracking changes instead of rescanning.
    private var trackingStrip: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(scanner.isLive ? Theme.good : Theme.ink3)
                .frame(width: 5, height: 5)
                .shadow(color: scanner.isLive ? Theme.good : .clear, radius: 4)
                .scaleEffect(pulse ? 1.5 : 1)
                .animation(.easeOut(duration: 0.45), value: pulse)

            Text(scanner.isLive ? "LIVE" : "SNAPSHOT")
                .font(Theme.mono(9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(scanner.isLive ? Theme.good : Theme.ink3)

            if scanner.isLive {
                Text("·").foregroundStyle(Theme.ink3.opacity(0.5))

                if let changed = scanner.lastChangeAt {
                    Text("updated \(Self.ago(changed))")
                        .font(Theme.mono(9)).foregroundStyle(Theme.ink2)
                } else {
                    Text("watching for changes")
                        .font(Theme.mono(9)).foregroundStyle(Theme.ink3)
                }

                if scanner.pendingDirectories > 0 {
                    Text("· \(scanner.pendingDirectories) queued")
                        .font(Theme.mono(9)).foregroundStyle(Theme.warning)
                }
            }

            Spacer(minLength: 4)

            if let cost = scanner.lastUpdateSeconds, scanner.updatesApplied > 0 {
                // A rescan of this folder took the whole progress sweep; this is
                // what the same change costs incrementally.
                Text("\(scanner.updatesApplied)× in \(Self.millis(cost))")
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.track.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
        .onChange(of: scanner.updatesApplied) { _, _ in
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { pulse = false }
        }
    }

    private static func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 2 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    private static func millis(_ seconds: TimeInterval) -> String {
        seconds < 0.001 ? "<1ms" : "\(Int((seconds * 1000).rounded()))ms"
    }

    private var scanButton: some View {
        Button {
            if scanner.isScanning {
                scanner.cancel()
            } else {
                scanner.scan(browser.currentURL)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: scanner.isScanning ? "stop.circle" : "magnifyingglass.circle")
                    .font(.system(size: 11))
                Text(scanner.isScanning ? "STOP" : "SCAN")
                    .font(Theme.mono(9.5, weight: .semibold))
            }
            .foregroundStyle(Theme.warning)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(scanner.isScanning ? "Cancel the scan" : "Scan this folder recursively")
    }

    private var scanningState: some View {
        HStack(spacing: 14) {
            // A real sweep: the arc advances with each 2,000-file batch rather
            // than spinning on a timer detached from progress.
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: 0.08 + 0.9 * sweepFraction)
                    .stroke(Theme.warning, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.warning.opacity(0.8), radius: 6)
                    .animation(.easeOut(duration: 0.4), value: sweepFraction)
                Text("\(Int(sweepFraction * 100))")
                    .font(Theme.mono(10, weight: .bold)).foregroundStyle(Theme.ink1)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(scanner.progressFiles.formatted()) files")
                    .font(Theme.mono(12, weight: .semibold)).foregroundStyle(Theme.ink1)
                Text(Self.size(scanner.progressBytes))
                    .font(Theme.mono(11)).foregroundStyle(Theme.warning)
                Text("walking the tree…")
                    .font(Theme.ui(10.5)).foregroundStyle(Theme.ink3)
            }
            Spacer()
        }
    }

    /// There's no total to divide by mid-walk, so this is a damped curve over
    /// files seen — honest as motion, never claiming a false percentage.
    private var sweepFraction: Double {
        let files = Double(scanner.progressFiles)
        return 1 - exp(-files / 40_000)
    }

    private var resultsState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.size(scanner.result.totalBytes))
                    .font(Theme.ui(24, weight: .bold)).foregroundStyle(Theme.ink1)
                Text("in \(scanner.result.filesScanned.formatted()) files")
                    .font(Theme.mono(10)).foregroundStyle(Theme.ink3)
                Spacer()
            }

            if scanner.result.skipped > 0 {
                Text("\(scanner.result.skipped) unreadable — grant Full Disk Access for a complete total")
                    .font(Theme.mono(9.5)).foregroundStyle(Theme.warning)
                    .lineLimit(2)
            }

            Divider().background(Theme.hairline2)

            HStack {
                HStack(spacing: 2) {
                    ForEach(Lens.allCases, id: \.self) { l in
                        Button {
                            lens = l
                            if l == .caches && scanner.cleanables.isEmpty && !scanner.isScanningCleanables {
                                scanner.scanCleanables()
                            }
                        } label: {
                            Text(l.rawValue)
                                .font(Theme.mono(9, weight: .semibold))
                                .foregroundStyle(lens == l ? Theme.ink1 : Theme.ink3)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(lens == l ? Theme.track : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Theme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

                Spacer()

                if lens == .caches && !scanner.cleanables.isEmpty {
                    Text(Self.size(scanner.totalCleanableBytes) + " cleanable")
                        .font(Theme.mono(9.5, weight: .semibold))
                        .foregroundStyle(Theme.accentSecondary)
                }
            }

            if lens == .largest {
                let maxBytes = scanner.result.largestFiles.first?.bytes ?? 1
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(scanner.result.largestFiles.prefix(20)) { file in
                            LargeFileRow(
                                file: file,
                                fraction: Double(file.bytes) / Double(maxBytes),
                                onDelete: { delete(file) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 280)
            } else {
                cleanablesList
            }
        }
    }

    private var cleanablesList: some View {
        Group {
            if scanner.isScanningCleanables {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                    Text("Scanning developer & app caches…").font(Theme.ui(11.5)).foregroundStyle(Theme.ink3)
                }
                .padding(.vertical, 12)
            } else if scanner.cleanables.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No large cleanable caches found (>10 MB).").font(Theme.ui(12)).foregroundStyle(Theme.ink3)
                    Button("Rescan Caches") { scanner.scanCleanables() }
                        .buttonStyle(.plain)
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(Theme.accentSecondary)
                }
                .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(scanner.cleanables) { item in
                            CleanableRow(
                                item: item,
                                onBrowse: {
                                    browser.navigate(to: URL(fileURLWithPath: item.path))
                                },
                                onClean: {
                                    let outcome = scanner.cleanArtifact(item)
                                    actions.report(outcome) { scanner.scanCleanables() }
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    /// The disk watcher picks the change up on its own, so the charts follow
    /// without a rescan — the whole point of tracking changes incrementally.
    private func delete(_ file: ScannedFile) {
        let url = URL(fileURLWithPath: file.path)
        let outcome = TrashService.trash(
            url,
            name: file.name,
            bytes: file.bytes,
            isDirectory: false,
            hasFullDiskAccess: browser.hasFullDiskAccess
        )
        actions.report(outcome) { browser.reload() }
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct CleanableRow: View {
    let item: CleanableArtifact
    let onBrowse: () -> Void
    let onClean: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(item.category)
                .font(Theme.mono(8.5, weight: .bold))
                .foregroundStyle(Theme.accentSecondary)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Theme.accentSecondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(Theme.ui(11.5, weight: .semibold)).foregroundStyle(Theme.ink1)
                    .lineLimit(1)
                Text("\(item.fileCount.formatted()) files")
                    .font(Theme.mono(9)).foregroundStyle(Theme.ink3)
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                .font(Theme.mono(10.5, weight: .semibold)).foregroundStyle(Theme.ink2)

            Button(action: onBrowse) {
                Image(systemName: "folder").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink3)
            .help("Browse in Files panel")

            Button(action: onClean) {
                Image(systemName: "trash").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.critical)
            .help("Move cache to Trash")
        }
        .padding(.vertical, 3)
    }
}

private struct LargeFileRow: View {
    let file: ScannedFile
    let fraction: Double
    let onDelete: () -> Void

    @Environment(FileBrowser.self) private var browser
    @State private var vanishing = false

    private var verdict: FileGuard {
        FileGuard.evaluate(URL(fileURLWithPath: file.path), hasFullDiskAccess: browser.hasFullDiskAccess)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(file.name)
                    .font(Theme.ui(11.5)).foregroundStyle(Theme.ink1)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))
                    .font(Theme.mono(10.5, weight: .semibold)).foregroundStyle(Theme.ink2)

                Button {
                    let parent = URL(fileURLWithPath: file.path).deletingLastPathComponent()
                    browser.navigate(to: parent)
                } label: {
                    Image(systemName: "arrow.right.circle").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Open folder in Files browser")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                } label: {
                    Image(systemName: "folder").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink3)
                .help("Reveal in Finder")

                // This list exists to answer "what can I delete?", so the
                // answer has to be actionable right here — and the icon says
                // whether it's even possible before the click.
                Button {
                    guard verdict.isAllowed else { onDelete(); return }
                    vanishing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { onDelete() }
                } label: {
                    Image(systemName: verdict.symbol).font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(verdict.isAllowed ? Theme.ink3 : Theme.warning.opacity(0.85))
                .help(verdict.isAllowed ? "Move to Trash" : verdict.explanation)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.track)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.warning.opacity(0.75))
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
        .help(file.path)
        .opacity(vanishing ? 0 : 1)
        .scaleEffect(y: vanishing ? 0.02 : 1, anchor: .top)
        .blur(radius: vanishing ? 3 : 0)
        .animation(.easeIn(duration: 0.26), value: vanishing)
    }
}
