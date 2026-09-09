import SwiftUI

struct FilesPanel: View {
    @Environment(FileBrowser.self) private var browser
    @Environment(DiskScanner.self) private var scanner
    @Binding var editing: FileEditTarget?
    @Environment(ActionCenter.self) private var actions
    @State private var revealed = false
    @State private var copiedCurrentPath = false
    @FocusState private var searchFocused: Bool
    /// Rows mid-exit. Held here rather than in the model so the animation can
    /// finish before the row is actually gone.
    @State private var vaporizing: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !browser.hasFullDiskAccess {
                fullDiskAccessBanner
            }

            breadcrumbBar

            if !browser.currentFolderGuard.isAllowed {
                folderGuardBanner(browser.currentFolderGuard)
            }

            if let error = browser.loadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                    Text(error).font(Theme.ui(12)).lineLimit(2)
                }
                .foregroundStyle(Theme.critical)
                .padding(.vertical, 4)
            }

            if browser.entries.isEmpty && browser.loadError == nil {
                Text("Empty folder.").font(Theme.ui(12.5)).foregroundStyle(Theme.ink3)
            } else if browser.filteredEntries.isEmpty {
                HStack(spacing: 8) {
                    Text("No items match this filter.")
                        .font(Theme.ui(12.5)).foregroundStyle(Theme.ink3)
                    Button("Clear filter") {
                        browser.searchQuery = ""
                        browser.categoryFilter = nil
                        browser.onlyFolders = false
                        browser.onlyStale = false
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
                .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(browser.filteredEntries.enumerated()), id: \.element.id) { index, entry in
                            let vanishing = vaporizing.contains(entry.id)
                            FileRow(
                                entry: entry,
                                onEdit: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        editing = FileEditTarget(entry: entry, renamer: browser)
                                    }
                                },
                                onDelete: { delete(entry) }
                            )
                            // The row visibly leaves before the model drops it,
                            // so a delete reads as something that happened
                            // rather than a row that was never there.
                            .opacity(vanishing ? 0 : 1)
                            .scaleEffect(y: vanishing ? 0.02 : 1, anchor: .top)
                            .blur(radius: vanishing ? 3 : 0)
                            .animation(.easeIn(duration: 0.26), value: vanishing)
                            // Rows fade in with a short stagger so changing
                            // directory reads as a transition, not a jump cut.
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 6)
                            .animation(
                                .easeOut(duration: 0.25).delay(min(Double(index) * 0.012, 0.3)),
                                value: revealed
                            )
                            Divider().background(Theme.hairline2)
                        }
                    }
                }
                .frame(maxHeight: 460)
            }

            Divider().background(Theme.hairline)
            storageTelemetryBar
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(accent: Theme.accent)
        .cornerBracket(color: Theme.accent)
        .onAppear { revealed = true }
        .onChange(of: browser.currentURL) { _, _ in
            browser.searchQuery = ""
            revealed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { revealed = true }
        }
    }

    /// Nothing touches the disk until the guard says it can, and the outcome
    /// always lands in the same banner.
    private func delete(_ entry: FileEntry) {
        let verdict = browser.permission(for: entry)
        guard verdict.isAllowed else {
            actions.reportBlocked(verdict)
            return
        }

        vaporizing.insert(entry.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            let outcome = browser.moveToTrash(entry)
            vaporizing.remove(entry.id)
            actions.report(outcome) { browser.reload() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(color: Theme.accent)
            Text("FILES").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)

            Spacer(minLength: 4)

            inlineSearch
            filterMenu

            Menu {
                ForEach(FileBrowser.SortOrder.allCases, id: \.self) { order in
                    Button(order.label.capitalized) { browser.sortOrder = order }
                }
            } label: {
                Text("SORT · \(browser.sortOrder.label)")
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                browser.showHidden.toggle()
            } label: {
                Image(systemName: browser.showHidden ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(browser.showHidden ? Theme.accent : Theme.ink3)
            }
            .buttonStyle(.plain)
            .help(browser.showHidden ? "Hide dotfiles" : "Show dotfiles")

            Button { browser.reload() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink3)
            .help("Reload folder")

            Button {
                scanner.scan(browser.currentURL)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: scanner.isScanning ? "stop.circle" : "radar")
                        .font(.system(size: 10))
                    Text(scanner.isScanning ? "SCANNING" : "SCAN")
                        .font(Theme.mono(9.5, weight: .semibold))
                }
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help(scanner.isScanning ? "Scan in progress" : "Scan this folder in Disk Radar")
        }
    }

    private var inlineSearch: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.ink3)

            TextField(
                "Filter",
                text: Binding(
                    get: { browser.searchQuery },
                    set: { browser.searchQuery = $0 }
                )
            )
            .textFieldStyle(.plain)
            .font(Theme.mono(11))
            .foregroundStyle(Theme.ink1)
            .focused($searchFocused)
            .frame(width: 90)

            if browser.searchQuery.isEmpty {
                Text("⌘F").font(Theme.mono(8.5)).foregroundStyle(Theme.ink3.opacity(0.6))
            } else {
                Button { browser.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(Theme.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(searchFocused ? Theme.accent.opacity(0.5) : Theme.hairline2, lineWidth: 1)
        )
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
        )
    }

    private var filterMenu: some View {
        Menu {
            Button("All Items") {
                browser.categoryFilter = nil
                browser.onlyFolders = false
                browser.onlyStale = false
            }
            Divider()
            Button("Folders Only") {
                browser.categoryFilter = nil
                browser.onlyFolders = true
                browser.onlyStale = false
            }
            Button("Stale (30d+)") {
                browser.categoryFilter = nil
                browser.onlyFolders = false
                browser.onlyStale = true
            }
            Divider()
            ForEach(FileCategory.allCases, id: \.self) { cat in
                Button(cat.label.capitalized) {
                    browser.categoryFilter = cat
                    browser.onlyFolders = false
                    browser.onlyStale = false
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(filterLabel)
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(isFiltered ? Theme.accent : Theme.ink3)
                if browser.staleCount > 0 && !browser.onlyStale {
                    Text("\(browser.staleCount)")
                        .font(Theme.mono(8.5, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by kind or age")
    }

    private var isFiltered: Bool {
        browser.categoryFilter != nil || browser.onlyFolders || browser.onlyStale
    }

    private var filterLabel: String {
        if browser.onlyFolders { return "FOLDERS" }
        if browser.onlyStale { return "STALE" }
        if let cat = browser.categoryFilter { return cat.label }
        return "ALL"
    }

    /// States plainly what's restricted and why, with the one action that can
    /// actually fix it — FDA has no in-app prompt.
    private var fullDiskAccessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.system(size: 12)).foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text("Limited to your home folder")
                    .font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.ink1)
                Text("Full Disk Access is needed for system paths and other users' files. macOS only allows granting it in System Settings.")
                    .font(Theme.ui(11)).foregroundStyle(Theme.ink3)
            }
            Spacer()
            Button("Open Settings") { browser.openFullDiskAccessSettings() }
                .buttonStyle(.plain)
                .font(Theme.mono(11))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.warning.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Theme.warning)
        }
        .padding(10)
        .background(Theme.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Said once for the whole folder rather than repeated on every row. In a
    /// place like /System that's the honest framing: it isn't that this file is
    /// special, it's that the location is.
    private func folderGuardBanner(_ verdict: FileGuard) -> some View {
        let tint = verdict == .needsFullDiskAccess ? Theme.warning : Theme.ink2
        return HStack(spacing: 9) {
            Image(systemName: verdict.symbol).font(.system(size: 11.5)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("This location is read-only · \(verdict.badge)")
                    .font(Theme.ui(11.5, weight: .semibold)).foregroundStyle(Theme.ink1)
                Text(verdict.explanation)
                    .font(Theme.ui(10.5)).foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if verdict.settingsFix {
                Button("Open Settings") { FileGuard.openFullDiskAccessSettings() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(10.5))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(tint)
            }
        }
        .padding(9)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button { browser.goUp() } label: {
                Image(systemName: "arrow.up").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(browser.canGoUp ? Theme.ink2 : Theme.ink3.opacity(0.4))
            .disabled(!browser.canGoUp)
            .help("Up one folder")

            Menu {
                ForEach(FileBrowser.shortcuts, id: \.label) { shortcut in
                    Button(shortcut.label) { browser.navigate(to: shortcut.url) }
                }
            } label: {
                Image(systemName: "bookmark").font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Jump to a folder")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(browser.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Text("/").font(Theme.mono(10)).foregroundStyle(Theme.ink3.opacity(0.5))
                        }
                        Button { browser.navigate(to: crumb.url) } label: {
                            Text(crumb.name)
                                .font(Theme.mono(10.5))
                                .foregroundStyle(index == browser.breadcrumbs.count - 1 ? Theme.ink1 : Theme.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let branch = browser.currentGitBranch {
                HStack(spacing: 3.5) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 8.5))
                    Text(branch).font(Theme.mono(8.5, weight: .bold))
                }
                .foregroundStyle(Theme.accentSecondary)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.accentSecondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                .help("Git Branch: \(branch)")
            }

            Spacer(minLength: 4)

            Button {
                DevAppLauncher.openInTerminal(browser.currentURL)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "terminal").font(.system(size: 9))
                    Text("TERMINAL").font(Theme.mono(8.5, weight: .semibold))
                }
                .foregroundStyle(Theme.copilotColor)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.copilotColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Open current folder in Terminal")

            if let defaultEditor = DevAppLauncher.defaultEditor {
                Menu {
                    ForEach(DevAppLauncher.availableEditors) { editor in
                        Button(editor.rawValue) {
                            DevAppLauncher.openInEditor(browser.currentURL, editor: editor)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: defaultEditor.iconName).font(.system(size: 9))
                        Text(defaultEditor.rawValue.uppercased()).font(Theme.mono(8.5, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accentSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.accentSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Open in code editor")
            }

            Button {
                browser.copyCurrentPath()
                copiedCurrentPath = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedCurrentPath = false }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copiedCurrentPath ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                    Text(copiedCurrentPath ? "COPIED" : "COPY PATH")
                        .font(Theme.mono(8.5, weight: .semibold))
                }
                .foregroundStyle(copiedCurrentPath ? Theme.good : Theme.ink3)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.track.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Copy current directory path")
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Theme.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private var storageTelemetryBar: some View {
        HStack(spacing: 12) {
            // Volume capacity & free gauge
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)

                Text(browser.volumeName)
                    .font(Theme.mono(9.5, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                // Mini horizontal gauge
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.track)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.accent, Theme.accentSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * browser.volumeUsageRatio))
                    }
                }
                .frame(width: 70, height: 4)

                Text("\(ByteCountFormatter.string(fromByteCount: browser.volumeFreeBytes, countStyle: .file)) FREE")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3)
            }

            Spacer()

            // Active folder metrics
            HStack(spacing: 10) {
                Text("\(browser.filteredEntries.count) ITEMS")
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(Theme.ink2)

                Text("·")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3.opacity(0.6))

                Text(ByteCountFormatter.string(fromByteCount: browser.totalFilteredBytes, countStyle: .file))
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(Theme.copilotColor)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.track.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct FileRow: View {
    let entry: FileEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(FileBrowser.self) private var browser
    @Environment(DiskScanner.self) private var scanner
    @State private var copied = false
    @State private var isHovered = false

    private var verdict: FileGuard { browser.permission(for: entry) }

    /// Directories have no size of their own — only a completed disk scan can
    /// fill this in, so it stays an em dash until one has run.
    private var sizeText: String {
        if entry.isDirectory {
            guard let bytes = scanner.size(forPath: entry.id) else { return "—" }
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        return ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Neon cyan hover scanline bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isHovered ? Theme.accent : Color.clear)
                .frame(width: 2.5, height: isHovered ? 18 : 0)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)

            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 11))
                .foregroundStyle(entry.isDirectory ? Theme.accent : (isHovered ? Theme.ink1 : Theme.ink3))
                .frame(width: 14)

            Button { browser.activate(entry) } label: {
                Text(entry.name)
                    .font(Theme.ui(12.5))
                    .foregroundStyle(isHovered ? Theme.ink1 : Theme.ink2)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(entry.isDirectory ? "Open folder" : "Open file")

            if entry.isStale && !entry.isDirectory {
                Text("30d+")
                    .font(Theme.mono(8.5, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                    .background(Theme.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    .help("Not opened in over 30 days")
            }

            Spacer()

            Text(sizeText)
                .font(Theme.mono(11))
                .foregroundStyle(entry.isDirectory && sizeText != "—" ? Theme.warning : (isHovered ? Theme.ink2 : Theme.ink3))
                .frame(width: 70, alignment: .trailing)

            Text(entry.addedAt == .distantPast ? "—" : entry.addedAt.formatted(date: .numeric, time: .omitted))
                .font(Theme.mono(11)).foregroundStyle(isHovered ? Theme.ink2 : Theme.ink3)
                .frame(width: 74, alignment: .trailing)

            HStack(spacing: 11) {
                rowButton("eye") {
                    browser.previewEntry = entry
                }
                .help("Preview (Space)")

                rowButton(copied ? "checkmark" : "doc.on.doc") {
                    browser.copyPath(for: entry)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                .help(copied ? "Copied!" : "Copy path")

                rowButton("folder") { browser.reveal(entry) }
                    .help("Reveal in Finder")
                rowButton("pencil") { onEdit() }
                    .help("Rename / info")

                // The affordance itself carries the verdict: a padlock where
                // the bin would be, so it's clear before the click — not an
                // error message after it.
                Button(action: onDelete) {
                    Image(systemName: verdict.symbol)
                        .font(.system(size: 11.5))
                        .foregroundStyle(verdict.isAllowed ? (isHovered ? Theme.ink2 : Theme.ink3) : Theme.warning.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help(verdict.isAllowed ? "Move to Trash" : verdict.explanation)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Theme.track.opacity(0.65) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func rowButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5))
                .foregroundStyle(isHovered ? Theme.ink2 : Theme.ink3)
        }
        .buttonStyle(.plain)
    }
}

