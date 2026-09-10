import AppKit
import SwiftUI

/// Cockpit Duplicate File & Stale Downloads Hunter.
/// Groups byte-for-byte clones identified via streaming SHA-256 digests,
/// flags large and aged downloads, and allows 1-click safe batch recycling to macOS Trash.
struct DuplicateHunterPanel: View {
    @Environment(DuplicateScanner.self) private var scanner
    @FocusState private var searchFocused: Bool

    enum HunterMode: String, CaseIterable {
        case duplicates = "EXACT DUPLICATES"
        case largeAndOld = "LARGE & OLD FILES"
    }

    @State private var mode: HunterMode = .duplicates
    @State private var confirmingTrash = false
    @State private var lastReclaimedBytes: Int64? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if scanner.isScanning {
                scanningProgressBar
            }
            toolbar

            switch mode {
            case .duplicates:
                duplicatesContent
            case .largeAndOld:
                largeAndOldContent
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.accent)
        .cornerBracket(color: Theme.accent)
        .onAppear {
            if scanner.duplicateSets.isEmpty && !scanner.isScanning {
                scanner.scan()
            }
        }
        .confirmationDialog(
            "RECYCLE SELECTED FILES TO TRASH",
            isPresented: $confirmingTrash,
            titleVisibility: .visible
        ) {
            Button("MOVE \(scanner.selectedFileIds.count) FILES TO TRASH (\(Formatters.bytes(scanner.totalSelectedBytes)))", role: .destructive) {
                scanner.trashSelected { reclaimed in
                    lastReclaimedBytes = reclaimed
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Safely move \(scanner.selectedFileIds.count) selected duplicate and stale files (\(Formatters.bytes(scanner.totalSelectedBytes))) to macOS Trash? All files are validated against FileGuard before moving.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(color: Theme.accent)
            Text("DUPLICATE & STALE DOWNLOADS HUNTER")
                .font(Theme.display(11))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)

            let setsCount = scanner.duplicateSets.count
            Text("\(setsCount) CLUSTERS")
                .font(Theme.mono(8.5, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.accent.opacity(0.15), in: Capsule())
                .foregroundStyle(Theme.accent)

            if scanner.totalReclaimableDuplicateBytes > 0 {
                Text("\(Formatters.bytes(scanner.totalReclaimableDuplicateBytes)) RECLAIMABLE")
                    .font(Theme.mono(8.5, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.warn.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.warn)
            }

            Spacer(minLength: 8)

            Button {
                scanner.scan()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(scanner.isScanning ? .degrees(360) : .zero)
                        .animation(scanner.isScanning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: scanner.isScanning)
                    Text(scanner.isScanning ? "PROBING..." : "SCAN CLONES")
                        .font(Theme.mono(9, weight: .bold))
                }
                .foregroundStyle(scanner.isScanning ? Theme.accent : Theme.ink2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(scanner.isScanning)
        }
    }

    // MARK: - Scanning Progress

    private var scanningProgressBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("SCANNING \(scanner.currentScanningFolder.uppercased()) · STREAMING SHA-256 HASHES")
                    .font(Theme.mono(8.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("\(Int(scanner.scanProgress * 100))%")
                    .font(Theme.mono(8.5, weight: .bold))
                    .foregroundStyle(Theme.ink2)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.violet],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(scanner.scanProgress)))
                }
            }
            .frame(height: 5)
        }
        .padding(10)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Mode picker
                HStack(spacing: 2) {
                    ForEach(HunterMode.allCases, id: \.self) { m in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                mode = m
                            }
                        } label: {
                            Text(m.rawValue)
                                .font(Theme.mono(9.5, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(mode == m ? Theme.accent.opacity(0.18) : Color.white.opacity(0.03))
                                .foregroundStyle(mode == m ? Theme.accent : Theme.ink3)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                // Category Filter Pills
                HStack(spacing: 4) {
                    categoryPill(title: "ALL", category: nil)
                    ForEach(DuplicateMediaKind.allCases, id: \.self) { cat in
                        categoryPill(title: cat.rawValue.components(separatedBy: " ").first ?? cat.rawValue, category: cat)
                    }
                }

                Spacer()

                // Inline Search
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.ink3)

                    TextField("Search...", text: Bindable(scanner).searchQuery)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink1)
                        .focused($searchFocused)
                        .frame(width: 100)

                    if !scanner.searchQuery.isEmpty {
                        Button {
                            scanner.searchQuery = ""
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
            }

            // Batch Action Strip
            HStack(spacing: 12) {
                if mode == .duplicates {
                    Button {
                        scanner.autoSelectDuplicates()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("AUTO-SELECT CLONES")
                                .font(Theme.mono(9, weight: .bold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if !scanner.selectedFileIds.isEmpty {
                    Button {
                        scanner.deselectAll()
                    } label: {
                        Text("DESELECT ALL")
                            .font(Theme.mono(9, weight: .bold))
                            .foregroundStyle(Theme.ink3)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !scanner.selectedFileIds.isEmpty {
                    Text("\(scanner.selectedFileIds.count) SELECTED · \(Formatters.bytes(scanner.totalSelectedBytes))")
                        .font(Theme.mono(9.5, weight: .bold))
                        .foregroundStyle(Theme.ink2)

                    Button {
                        confirmingTrash = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                            Text("TRASH SELECTED (\(Formatters.bytes(scanner.totalSelectedBytes)))")
                                .font(Theme.mono(9.5, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.warn.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.warn, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.015), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func categoryPill(title: String, category: DuplicateMediaKind?) -> some View {
        let isSelected = scanner.selectedCategory == category
        return Button {
            scanner.selectedCategory = category
        } label: {
            Text(title)
                .font(Theme.mono(8.5, weight: .bold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(isSelected ? Theme.accent.opacity(0.2) : Color.white.opacity(0.03))
                .foregroundStyle(isSelected ? Theme.accent : Theme.ink3)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Duplicates Content

    private var duplicatesContent: some View {
        let sets = scanner.filteredDuplicateSets

        return Group {
            if sets.isEmpty {
                if scanner.isScanning {
                    scanningEmptyView
                } else {
                    emptyState(
                        title: "NO DUPLICATE FILES FOUND",
                        subtitle: "Your scanned folders contain no byte-for-byte duplicate copies."
                    )
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sets) { set in
                            duplicateSetCard(set: set)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func duplicateSetCard(set: DuplicateSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cluster Header
            HStack(spacing: 10) {
                if let first = set.files.first {
                    Image(systemName: first.category.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                }

                Text(set.files.first?.name ?? "Duplicate File")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(Theme.ink1)
                    .lineLimit(1)

                Text(Formatters.bytes(set.fileSize))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.ink3)

                Spacer()

                Text("RECLAIMABLE: \(Formatters.bytes(set.reclaimableBytes))")
                    .font(Theme.mono(9, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.warn.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.warn)

                Text("SHA256: \(String(set.hash.prefix(8)))")
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.ink3.opacity(0.7))
            }
            .padding(.bottom, 4)

            // File items within cluster
            VStack(spacing: 4) {
                ForEach(Array(set.files.enumerated()), id: \.element.id) { index, file in
                    duplicateFileRow(file: file, isOriginal: index == 0)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }

    private func duplicateFileRow(file: ScannedFileItem, isOriginal: Bool) -> some View {
        let isSelected = scanner.selectedFileIds.contains(file.id)

        return HStack(spacing: 10) {
            // Checkbox
            Button {
                scanner.toggleSelection(for: file.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.warn : Theme.ink3)
            }
            .buttonStyle(.plain)

            // Original vs Clone pill
            if isOriginal {
                Text("ORIGINAL")
                    .font(Theme.mono(7.5, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.accent)
            } else {
                Text("CLONE")
                    .font(Theme.mono(7.5, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .foregroundStyle(Theme.ink3)
            }

            // Path & date
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(Theme.mono(8.5))
                    .foregroundStyle(isSelected ? Theme.warn.opacity(0.8) : Theme.ink2)
                    .lineLimit(1)

                Text("Modified \(file.ageInDays) days ago · \(file.modificationDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.mono(7.5))
                    .foregroundStyle(Theme.ink3)
            }

            Spacer(minLength: 6)

            // Reveal in Finder
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.warn.opacity(0.08) : Color.white.opacity(0.015))
        )
    }

    // MARK: - Large & Old Content

    private var largeAndOldContent: some View {
        let items = scanner.filteredLargeAndOld

        return Group {
            if items.isEmpty {
                emptyState(
                    title: "NO STALE OR OVERSIZED FILES DETECTED",
                    subtitle: "No files found exceeding 250MB or untouched for more than 90 days."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { item in
                            largeAndOldRow(item: item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func largeAndOldRow(item: ScannedFileItem) -> some View {
        let isSelected = scanner.selectedFileIds.contains(item.id)

        return HStack(spacing: 10) {
            Button {
                scanner.toggleSelection(for: item.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.warn : Theme.ink3)
            }
            .buttonStyle(.plain)

            Image(systemName: item.category.icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(Theme.mono(10.5, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.warn : Theme.ink1)
                    .lineLimit(1)

                Text(item.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if item.sizeBytes > 250 * 1024 * 1024 {
                Text("LARGE")
                    .font(Theme.mono(7.5, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Theme.amber.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.amber)
            }

            if item.ageInDays > 90 {
                Text("\(item.ageInDays)d OLD")
                    .font(Theme.mono(7.5, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .foregroundStyle(Theme.ink3)
            }

            Text(Formatters.bytes(item.sizeBytes))
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.ink2)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.warn.opacity(0.08) : Color.white.opacity(0.02))
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Theme.warn.opacity(0.3) : Theme.line, lineWidth: 1))
    }

    // MARK: - Empty & Loading States

    private var scanningEmptyView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("STREAMING SHA-256 HASHES & BUCKETING SIZES...")
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
}
