import SwiftUI
import AppKit
import AVKit
import PDFKit

struct FilePreviewOverlay: View {
    let entry: FileEntry
    let onDismiss: () -> Void

    @State private var highlightedLines: [AttributedString] = []
    @State private var lineCount: Int = 0
    @State private var imageResolution: CGSize?
    @State private var nsImage: NSImage?
    @State private var avPlayer: AVPlayer?
    @State private var isVideo = false
    @State private var isAudio = false
    @State private var isPDF = false
    @State private var isBinary = false
    @State private var copied = false
    @State private var isAudioPlaying = false
    @State private var audioProgress: Double = 0
    @State private var audioDuration: Double = 0
    @State private var audioTimeText: String = "00:00 / 00:00"
    @State private var audioTimeObserver: Any?
    @State private var hexRows: [HexRow] = []

    var body: some View {
        ZStack {
            // Ambient Backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { dismissAndCleanup() }

            VStack(spacing: 0) {
                header
                Divider().background(Theme.hairline2)
                metadataBar
                Divider().background(Theme.hairline2)

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().background(Theme.hairline2)
                actionBar
            }
            .frame(width: 780, height: 580)
            .glassPanel(cornerRadius: 12, accent: Theme.accent)
            .cornerBracket(color: Theme.accent)
            .shadow(color: Theme.accent.opacity(0.22), radius: 28)
        }
        .onAppear { loadPreviewData() }
        .onDisappear { cleanupPlayback() }
        .background(
            Button("") { dismissAndCleanup() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        )
    }

    private func dismissAndCleanup() {
        cleanupPlayback()
        onDismiss()
    }

    private func cleanupPlayback() {
        if let observer = audioTimeObserver, let player = avPlayer {
            player.removeTimeObserver(observer)
            audioTimeObserver = nil
        }
        avPlayer?.pause()
        avPlayer = nil
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForEntry)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)

            Text(entry.name)
                .font(Theme.mono(13, weight: .bold))
                .foregroundStyle(Theme.ink1)
                .lineLimit(1)

            Text(entry.category.label)
                .font(Theme.mono(8.5, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.ink2)

            Button(action: dismissAndCleanup) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var iconForEntry: String {
        if entry.isDirectory { return "folder.fill" }
        if isVideo { return "film.fill" }
        if isAudio { return "waveform" }
        if isPDF { return "doc.richtext.fill" }
        if nsImage != nil { return "photo.fill" }
        switch entry.category {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .media: return "play.rectangle.fill"
        case .archive: return "archivebox.fill"
        case .document: return "doc.text.fill"
        default: return "doc.fill"
        }
    }

    // MARK: - Metadata Bar

    private var metadataBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Text("MODIFIED").font(Theme.mono(9, weight: .semibold)).foregroundStyle(Theme.ink3)
                Text(entry.addedAt.formatted(date: .numeric, time: .standard))
                    .font(Theme.mono(10.5)).foregroundStyle(Theme.ink2)
            }

            if lineCount > 0 {
                HStack(spacing: 5) {
                    Text("LINES").font(Theme.mono(9, weight: .semibold)).foregroundStyle(Theme.ink3)
                    Text("\(lineCount)").font(Theme.mono(10.5, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            } else if let imageResolution {
                HStack(spacing: 5) {
                    Text("RESOLUTION").font(Theme.mono(9, weight: .semibold)).foregroundStyle(Theme.ink3)
                    Text("\(Int(imageResolution.width))×\(Int(imageResolution.height)) px")
                        .font(Theme.mono(10.5, weight: .semibold)).foregroundStyle(Theme.copilotColor)
                }
            } else if isAudio || isVideo {
                HStack(spacing: 5) {
                    Text("MEDIA").font(Theme.mono(9, weight: .semibold)).foregroundStyle(Theme.ink3)
                    Text(isVideo ? "VIDEO STREAM" : "AUDIO STREAM")
                        .font(Theme.mono(10.5, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            } else if isPDF {
                HStack(spacing: 5) {
                    Text("FORMAT").font(Theme.mono(9, weight: .semibold)).foregroundStyle(Theme.ink3)
                    Text("PDF DOCUMENT")
                        .font(Theme.mono(10.5, weight: .semibold)).foregroundStyle(Theme.accentSecondary)
                }
            } else if isBinary {
                HStack(spacing: 5) {
                    Text("FORMAT").font(Theme.mono(9, weight: .semibold)).foregroundStyle(Theme.ink3)
                    Text("BINARY STREAM")
                        .font(Theme.mono(10.5, weight: .semibold)).foregroundStyle(Theme.warning)
                }
            }

            Spacer()

            Text(entry.url.path)
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.ink3.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 18).padding(.vertical, 7)
        .background(Theme.track.opacity(0.5))
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let player = avPlayer, isVideo {
            // Video playback
            ZStack {
                Color.black
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(12)
            }
        } else if let player = avPlayer, isAudio {
            // Cyberpunk Audio HUD
            audioPlayerCard(player: player)
        } else if isPDF {
            // PDF Document View
            PDFKitRepresentedView(url: entry.url)
                .padding(6)
                .background(Theme.page)
        } else if let nsImage {
            // Image with dark checkboard canvas
            ZStack {
                Theme.page.opacity(0.8)
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
                    .shadow(color: .black.opacity(0.6), radius: 12)
            }
        } else if !highlightedLines.isEmpty {
            // Code preview with Syntax Highlighting & Line Numbers
            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers gutter
                    VStack(alignment: .trailing, spacing: 3) {
                        ForEach(1...highlightedLines.count, id: \.self) { num in
                            Text("\(num)")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.ink3.opacity(0.5))
                                .frame(height: 18)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                    .background(Theme.track.opacity(0.8))

                    // Highlighted code lines
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(0..<highlightedLines.count, id: \.self) { idx in
                            Text(highlightedLines[idx])
                                .font(Theme.mono(11))
                                .frame(height: 18, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                }
            }
            .textSelection(.enabled)
            .background(Theme.page.opacity(0.85))
        } else if isBinary {
            // Fallback for non-text/binary files with actionable launches
            binaryFallbackView
        } else if entry.isDirectory {
            VStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.accent)
                Text(entry.name)
                    .font(Theme.display(15, weight: .bold)).foregroundStyle(Theme.ink1)
                Text("Directory · Browse contents in Files or open in Terminal / Editor below")
                    .font(Theme.ui(11.5)).foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Decoding file stream...")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Audio Player Card

    private func audioPlayerCard(player: AVPlayer) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Glowing animated audio visualizer
            HStack(spacing: 5) {
                ForEach(0..<28, id: \.self) { i in
                    let baseHeight: CGFloat = isAudioPlaying ? CGFloat([14, 28, 48, 22, 60, 36, 18, 52, 42, 26, 64, 30, 20, 56, 44, 18, 38, 54, 28, 62, 34, 16, 48, 24, 58, 32, 14, 40][i % 28]) : 8
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accentSecondary],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 4.5, height: baseHeight)
                        .animation(.easeInOut(duration: 0.25).repeatForever(autoreverses: true), value: isAudioPlaying)
                }
            }
            .frame(height: 70)
            .padding(.vertical, 8)

            VStack(spacing: 6) {
                Text(entry.name)
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                Text(audioTimeText)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            // Controls
            HStack(spacing: 20) {
                Button {
                    player.seek(to: .zero)
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink2)
                }
                .buttonStyle(.plain)

                Button {
                    if isAudioPlaying {
                        player.pause()
                        isAudioPlaying = false
                    } else {
                        player.play()
                        isAudioPlaying = true
                    }
                } label: {
                    Image(systemName: isAudioPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 10)
                }
                .buttonStyle(.plain)

                Button {
                    let forward = CMTime(seconds: 15, preferredTimescale: 600)
                    player.seek(to: player.currentTime() + forward)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink2)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page.opacity(0.8))
    }

    // MARK: - Binary Fallback & Cyberpunk Hex Matrix Inspector

    private var binaryFallbackView: some View {
        VStack(spacing: 0) {
            // Hex Matrix subheader & action buttons
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                    Text("HEX MATRIX INSPECTOR")
                        .font(Theme.mono(9.5, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }

                Text("·")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink3.opacity(0.6))

                Text("First \(min(2048, entry.sizeBytes)) bytes")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3)

                Spacer()

                Button {
                    DevAppLauncher.openInDefaultApp(entry.url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app").font(.system(size: 9))
                        Text("Default App").font(Theme.mono(9.5, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(Theme.accent)

                Button {
                    DevAppLauncher.openQuickLook(entry.url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye").font(.system(size: 9))
                        Text("Quick Look").font(Theme.mono(9.5, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.track, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.track.opacity(0.45))

            Divider().background(Theme.hairline2)

            if !hexRows.isEmpty {
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 12) {
                            Text("OFFSET").frame(width: 72, alignment: .leading)
                            Text("00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F").frame(width: 330, alignment: .leading)
                            Text("ASCII DECODE").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundStyle(Theme.ink3.opacity(0.7))
                        .padding(.bottom, 4)

                        ForEach(hexRows) { row in
                            HStack(spacing: 12) {
                                Text(row.offset)
                                    .font(Theme.mono(10.5))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 72, alignment: .leading)

                                Text(row.hexDisplay)
                                    .font(Theme.mono(10.5))
                                    .foregroundStyle(Theme.warning)
                                    .frame(width: 330, alignment: .leading)

                                Text(row.ascii)
                                    .font(Theme.mono(10.5))
                                    .foregroundStyle(Theme.copilotColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 16)
                        }
                    }
                    .padding(12)
                }
                .textSelection(.enabled)
                .background(Theme.page.opacity(0.85))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.ink3)
                    Text("No byte data available")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                DevAppLauncher.openInTerminal(entry.url)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "terminal").font(.system(size: 10))
                    Text("Terminal").font(Theme.mono(10.5, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.track, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(Theme.ink2)
            .help("Open directory in Terminal")

            if !DevAppLauncher.availableEditors.isEmpty {
                Menu {
                    ForEach(DevAppLauncher.availableEditors) { editor in
                        Button(editor.rawValue) {
                            DevAppLauncher.openInEditor(entry.url, editor: editor)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: DevAppLauncher.defaultEditor?.iconName ?? "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 10))
                        Text(DevAppLauncher.defaultEditor?.rawValue ?? "Editor")
                            .font(Theme.mono(10.5, weight: .semibold))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.track, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(Theme.ink2)
                .help("Open in code editor")
            }

            Button {
                DevAppLauncher.openInDefaultApp(entry.url)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.forward.square").font(.system(size: 10))
                    Text("Default App").font(Theme.mono(10.5, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.track, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(Theme.ink2)
            .help("Open with macOS default application")

            Button {
                DevAppLauncher.openQuickLook(entry.url)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "eye").font(.system(size: 10))
                    Text("Quick Look").font(Theme.mono(10.5, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.track, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(Theme.ink2)
            .help("Launch native macOS Quick Look")

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url.path, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                    Text(copied ? "Copied" : "Copy Path").font(Theme.mono(10.5, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(copied ? Theme.good.opacity(0.18) : Theme.track, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(copied ? Theme.good : Theme.ink2)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 10))
                    Text("Reveal").font(Theme.mono(10.5, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(Theme.accent)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Theme.panel)
    }

    // MARK: - Data Loading

    private func loadPreviewData() {
        if entry.isDirectory { return }

        let ext = entry.url.pathExtension.lowercased()

        // 1. Media: Video & Audio
        let videoExtensions = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]
        let audioExtensions = ["mp3", "wav", "m4a", "aac", "flac", "ogg"]

        if videoExtensions.contains(ext) || (entry.category == .media && !audioExtensions.contains(ext)) {
            isVideo = true
            let player = AVPlayer(url: entry.url)
            avPlayer = player
            player.play()
            return
        }

        if audioExtensions.contains(ext) {
            isAudio = true
            let player = AVPlayer(url: entry.url)
            avPlayer = player
            setupAudioObserver(player: player)
            player.play()
            isAudioPlaying = true
            return
        }

        // 2. PDF Document
        if ext == "pdf" {
            isPDF = true
            return
        }

        // 3. Image files
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "bmp", "tiff", "ico"]
        if entry.category == .image || imageExtensions.contains(ext) {
            DispatchQueue.global(qos: .userInitiated).async {
                var loaded: NSImage?
                if let data = try? Data(contentsOf: entry.url, options: [.mappedIfSafe]) {
                    loaded = NSImage(data: data)
                }
                if loaded == nil {
                    loaded = NSImage(contentsOfFile: entry.url.path)
                }
                if loaded == nil {
                    loaded = NSImage(contentsOf: entry.url)
                }

                DispatchQueue.main.async {
                    if let img = loaded {
                        self.nsImage = img
                        self.imageResolution = CGSize(width: img.size.width, height: img.size.height)
                    } else {
                        // Could not decode as bitmap image, try loading text (e.g. SVG source) or mark binary
                        self.loadTextContent()
                    }
                }
            }
            return
        }

        // 4. Code / Text files
        loadTextContent()
    }

    private func setupAudioObserver(player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        audioTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let currentSec = time.seconds.isFinite ? time.seconds : 0
            let durationSec = player.currentItem?.duration.seconds.isFinite == true ? (player.currentItem?.duration.seconds ?? 0) : 0

            self.audioDuration = durationSec
            if durationSec > 0 {
                self.audioProgress = currentSec / durationSec
            }

            let curM = Int(currentSec) / 60
            let curS = Int(currentSec) % 60
            let durM = Int(durationSec) / 60
            let durS = Int(durationSec) % 60
            self.audioTimeText = String(format: "%02d:%02d / %02d:%02d", curM, curS, durM, durS)
        }
    }

    private func loadTextContent() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let handle = try? FileHandle(forReadingFrom: entry.url) else {
                DispatchQueue.main.async { isBinary = true }
                return
            }
            defer { try? handle.close() }

            let maxBytes = 512 * 1024
            guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else {
                DispatchQueue.main.async {
                    highlightedLines = []
                    lineCount = 0
                }
                return
            }

            if let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                let lines = string.components(separatedBy: "\n")
                let lang = SyntaxHighlighter.Language.detect(from: entry.url)
                let previewLines = Array(lines.prefix(600))
                let highlighted = previewLines.map { SyntaxHighlighter.highlight(line: $0, language: lang) }

                DispatchQueue.main.async {
                    self.highlightedLines = highlighted
                    self.lineCount = lines.count
                }
            } else {
                let rows = HexDumper.dump(data: data.prefix(2048))
                DispatchQueue.main.async {
                    self.hexRows = rows
                    self.isBinary = true
                }
            }
        }
    }
}

// MARK: - Hex Dump Model & Engine

struct HexRow: Identifiable, Sendable {
    let id: Int
    let offset: String
    let hexDisplay: String
    let ascii: String
}

enum HexDumper {
    static func dump(data: Data) -> [HexRow] {
        var rows: [HexRow] = []
        let chunkSize = 16
        for chunkStart in stride(from: 0, to: data.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, data.count)
            let chunk = data[chunkStart..<chunkEnd]

            let offsetStr = String(format: "%08X", chunkStart)
            var hexParts1: [String] = []
            var hexParts2: [String] = []
            var asciiChars: [Character] = []

            for (idx, byte) in chunk.enumerated() {
                let hex = String(format: "%02X", byte)
                if idx < 8 {
                    hexParts1.append(hex)
                } else {
                    hexParts2.append(hex)
                }
                if byte >= 32 && byte <= 126 {
                    asciiChars.append(Character(UnicodeScalar(byte)))
                } else {
                    asciiChars.append(".")
                }
            }

            let hex1 = hexParts1.joined(separator: " ")
            let hex2 = hexParts2.joined(separator: " ")
            let hexFull = hex2.isEmpty ? hex1 : "\(hex1)  \(hex2)"
            let paddedHex = hexFull.padding(toLength: 48, withPad: " ", startingAt: 0)

            rows.append(HexRow(
                id: chunkStart,
                offset: offsetStr,
                hexDisplay: paddedHex,
                ascii: String(asciiChars)
            ))
        }
        return rows
    }
}


// MARK: - PDFKit NSViewRepresentable

struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
