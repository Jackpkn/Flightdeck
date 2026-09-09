import SwiftUI
import AppKit

struct DownloadsPanel: View {
    @Environment(DownloadsWatcher.self) private var watcher
    @Binding var editing: FileEditTarget?
    @State private var categoryFilter: FileCategory?
    @State private var selectedIds: Set<String> = []

    private var filtered: [FileEntry] {
        guard let categoryFilter else { return watcher.files }
        return watcher.files.filter { $0.category == categoryFilter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LiveDot(color: Theme.accentSecondary)
                Text("DOWNLOADS").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)

                Spacer(minLength: 6)

                if watcher.staleCount > 0 {
                    Text("\(watcher.staleCount) STALE")
                        .font(Theme.mono(9, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                        .help("Not opened in over 30 days")
                }

                categoryMenu
                duplicateButton
            }

            if filtered.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { entry in
                                DownloadRow(
                                    entry: entry,
                                    isSelected: selectedIds.contains(entry.id),
                                    isDuplicate: watcher.duplicateIds.contains(entry.id),
                                    onToggleSelect: {
                                        if selectedIds.contains(entry.id) {
                                            selectedIds.remove(entry.id)
                                        } else {
                                            selectedIds.insert(entry.id)
                                        }
                                    },
                                    onEdit: {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            editing = FileEditTarget(entry: entry, renamer: watcher)
                                        }
                                    }
                                )
                                Divider().background(Theme.hairline2)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity)

                    // Floating Bulk Actions Bar
                    if !selectedIds.isEmpty {
                        floatingActionBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.accentSecondary)
        .cornerBracket(color: Theme.accentSecondary)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                    .frame(width: 50, height: 50)
                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
            }

            Text("NO DOWNLOADS DETECTED · SYSTEM CLEAN")
                .font(Theme.mono(10.5, weight: .bold))
                .foregroundStyle(Theme.ink2)

            Text("Incoming files to ~/Downloads appear here automatically.")
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var floatingActionBar: some View {
        HStack(spacing: 10) {
            Text("\(selectedIds.count) SELECTED")
                .font(Theme.mono(9.5, weight: .bold))
                .foregroundStyle(Theme.ink1)

            Button {
                for id in selectedIds {
                    if let entry = watcher.files.first(where: { $0.id == id }) {
                        _ = watcher.moveToTrash(entry)
                    }
                }
                selectedIds.removeAll()
                CockpitAudio.playAlert()
                watcher.reload()
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "trash").font(.system(size: 9))
                    Text("DELETE SELECTED").font(Theme.mono(9, weight: .bold))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.critical.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Theme.critical)

            Button {
                let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                NSWorkspace.shared.open(downloads)
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "folder").font(.system(size: 9))
                    Text("OPEN FOLDER").font(Theme.mono(9, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.track, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Theme.ink2)

            Spacer()

            Button {
                selectedIds.removeAll()
            } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 8)
        .padding(.bottom, 6)
    }

    private var categoryMenu: some View {
        Menu {
            Button("All") { categoryFilter = nil }
            Divider()
            ForEach(FileCategory.allCases, id: \.self) { category in
                Button(category.label.capitalized) { categoryFilter = category }
            }
        } label: {
            HStack(spacing: 4) {
                Text(categoryFilter?.label ?? "ALL")
                    .font(Theme.mono(9.5, weight: .semibold))
                Text("\(filtered.count)")
                    .font(Theme.mono(9)).foregroundStyle(Theme.ink3.opacity(0.8))
            }
            .foregroundStyle(categoryFilter == nil ? Theme.ink3 : Theme.accentSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by file type")
    }

    private var duplicateButton: some View {
        Button {
            watcher.findDuplicates()
        } label: {
            HStack(spacing: 4) {
                if watcher.isScanningDuplicates {
                    ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                }
                if watcher.lastDuplicateScan != nil && !watcher.isScanningDuplicates {
                    Text("\(watcher.duplicateIds.count)")
                        .font(Theme.mono(9, weight: .semibold))
                }
            }
            .foregroundStyle(watcher.duplicateIds.isEmpty ? Theme.ink3 : Theme.critical)
        }
        .buttonStyle(.plain)
        .disabled(watcher.isScanningDuplicates)
        .help("Find duplicate files by content hash")
    }
}

private struct DownloadRow: View {
    let entry: FileEntry
    let isSelected: Bool
    let isDuplicate: Bool
    let onToggleSelect: () -> Void
    let onEdit: () -> Void

    @Environment(DownloadsWatcher.self) private var watcher
    @Environment(ActionCenter.self) private var actions
    @State private var isHovered = false

    private var iconInfo: (name: String, color: Color) {
        Self.iconAndColor(for: entry.url, category: entry.category)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox selector
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.ink3.opacity(0.6))
            }
            .buttonStyle(.plain)

            // Colored SF Symbol badge
            Image(systemName: iconInfo.name)
                .font(.system(size: 10.5))
                .foregroundStyle(iconInfo.color)
                .frame(width: 16)

            Text(Self.extensionTag(entry.url))
                .font(Theme.mono(8.5, weight: .bold))
                .foregroundStyle(iconInfo.color)
                .padding(.horizontal, 4).padding(.vertical, 1.5)
                .background(iconInfo.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 2.5))
                .frame(width: 38, alignment: .center)

            Text(entry.name)
                .font(Theme.ui(12)).foregroundStyle(Theme.ink1)
                .lineLimit(1)

            if isDuplicate {
                Text("DUP")
                    .font(Theme.mono(8, weight: .semibold))
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 3.5).padding(.vertical, 1)
                    .background(Theme.critical.opacity(0.15), in: RoundedRectangle(cornerRadius: 2.5))
                    .help("Identical content to another file here")
            }

            if entry.isStale {
                Text("30d+")
                    .font(Theme.mono(8, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 3.5).padding(.vertical, 1)
                    .background(Theme.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 2.5))
                    .help("Not opened in over 30 days")
            }

            Spacer()

            Text(Self.sizeString(entry.sizeBytes))
                .font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                .frame(width: 60, alignment: .trailing)

            Text(entry.addedAt.formatted(date: .omitted, time: .shortened))
                .font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                .frame(width: 60, alignment: .trailing)

            HStack(spacing: 10) {
                rowButton("arrow.up.forward.square") { watcher.open(entry) }
                    .help("Open")
                rowButton("folder") { watcher.reveal(entry) }
                    .help("Reveal in Finder")
                rowButton("pencil") { onEdit() }
                    .help("Edit")
                rowButton("trash") {
                    let outcome = watcher.moveToTrash(entry)
                    actions.report(outcome) { watcher.reload() }
                }
                .help("Move to Trash")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Theme.accent.opacity(0.08) : (isHovered ? Theme.track.opacity(0.5) : Color.clear))
        )
        .onHover { isHovered = $0 }
    }

    private func rowButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink3)
    }

    private static func iconAndColor(for url: URL, category: FileCategory) -> (name: String, color: Color) {
        switch category {
        case .image:
            return ("photo.fill", Theme.accent)
        case .code:
            return ("chevron.left.forwardslash.chevron.right", Theme.accentSecondary)
        case .archive:
            return ("archivebox.fill", Theme.critical)
        case .installer:
            return ("shippingbox.fill", Theme.warning)
        case .media:
            return ("play.rectangle.fill", Theme.copilotColor)
        case .document:
            return ("doc.text.fill", Color(hex: 0x38bdf8))
        case .other:
            return ("doc.fill", Theme.ink3)
        }
    }

    private static func sizeString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func extensionTag(_ url: URL) -> String {
        let ext = url.pathExtension
        return ext.isEmpty ? "FILE" : ext.uppercased()
    }
}
