import SwiftUI
import QuickLookThumbnailing

/// Presented at the DashboardView level — same tier as the command palette —
/// so the flip-open card sits centered over the whole window with a full
/// backdrop, instead of being pinned inside the Downloads panel's own narrow
/// column frame.
/// Anything that can rename a real file on disk. Both the downloads watcher
/// and the file browser do — and the overlay must act on whichever one the
/// entry actually came from, or it renames in the wrong folder.
protocol FileRenaming: AnyObject {
    func rename(_ entry: FileEntry, to newName: String)
}

struct FileEditTarget: Identifiable {
    var id: String { entry.id }
    let entry: FileEntry
    let renamer: any FileRenaming
}

struct DownloadEditOverlay: View {
    let target: FileEditTarget
    let onDismiss: () -> Void

    private var entry: FileEntry { target.entry }

    @State private var name: String = ""
    @State private var flipped = false
    @State private var thumbnail: NSImage?
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("EDIT FILE").font(Theme.display(12)).tracking(0.6).foregroundStyle(Theme.ink3)
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink3)
                }

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(Theme.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline2, lineWidth: 1)
                        )
                }

                TextField("File name", text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.ui(16, weight: .semibold))
                    .foregroundStyle(Theme.ink1)
                    .focused($nameFocused)
                    .padding(10)
                    .background(Theme.track, in: RoundedRectangle(cornerRadius: 7))
                    .onSubmit(save)

                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(label: "PATH", value: entry.url.deletingLastPathComponent().path)
                    DetailRow(label: "SIZE", value: ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                    DetailRow(label: "ADDED", value: entry.addedAt.formatted(date: .abbreviated, time: .shortened))
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: dismiss)
                        .buttonStyle(.plain)
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.ink3)
                    Button("Save", action: save)
                        .buttonStyle(.plain)
                        .font(Theme.ui(12.5, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.accentSecondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(Theme.accentSecondary)
                }
            }
            .padding(20)
            .frame(width: 380)
            .glassPanel(cornerRadius: 14, accent: Theme.accentSecondary)
            .cornerBracket(color: Theme.accentSecondary)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
            .rotation3DEffect(.degrees(flipped ? 0 : 90), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .opacity(flipped ? 1 : 0)
        }
        .onAppear {
            name = entry.name
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                flipped = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                nameFocused = true
            }
            loadThumbnail()
        }
    }

    /// Real QuickLook thumbnail — the same representation Finder shows, so a
    /// PDF or image is recognizable before you act on it.
    private func loadThumbnail() {
        let request = QLThumbnailGenerator.Request(
            fileAt: entry.url,
            size: CGSize(width: 640, height: 360),
            scale: 2,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let representation else { return }
            DispatchQueue.main.async {
                thumbnail = representation.nsImage
            }
        }
    }

    private func save() {
        target.renamer.rename(entry, to: name)
        dismiss()
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            onDismiss()
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(Theme.mono(10, weight: .semibold)).foregroundStyle(Theme.ink3).frame(width: 52, alignment: .leading)
            Text(value).font(Theme.mono(11)).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.middle)
        }
    }
}
