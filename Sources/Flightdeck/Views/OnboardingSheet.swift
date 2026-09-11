import SwiftUI
import AppKit

/// Shown once, on first launch.
///
/// Flightdeck reads a lot of local data and can write one file. Saying so plainly
/// before it does anything is both the honest thing and the thing that makes people
/// comfortable installing the integration — and without the integration the app is
/// stuck in its degraded, transcripts-only mode, which is how most users would
/// otherwise form their first impression of it.
struct OnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Set once the sheet has been completed or dismissed, so it never returns.
    static let seenKey = "flightdeck.onboarding_seen"

    static var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: seenKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    @State private var step = 0
    @State private var installStatus: ClaudeIntegrationInstaller.Status?
    @State private var installNotes: [String] = []
    @State private var installError: String?

    private var settingsURL: URL { ClaudeIntegrationInstaller.defaultSettingsURL() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Theme.hairline)
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().background(Theme.hairline)
            footer
        }
        .frame(width: 600, height: 520)
        .background(Theme.page)
        .onAppear(perform: refreshStatus)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "speedometer")
                .font(.system(size: 17))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("WELCOME TO FLIGHTDECK")
                    .font(Theme.display(14, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.ink1)
                Text("Your machine and your Claude Code spend, in one place")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer()
            Text("\(step + 1) / 3")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: privacyStep
        case 1: integrationStep
        default: tourStep
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .font(Theme.ui(12))
            }
            Spacer()
            Button(step == 2 ? "Skip" : "Skip setup") { finish() }
                .font(Theme.ui(12))
                .keyboardShortcut(.cancelAction)
            Button(step == 2 ? "Get started" : "Next") {
                if step == 2 { finish() } else { step += 1 }
            }
            .font(Theme.ui(12, weight: .semibold))
            .keyboardShortcut(.defaultAction)
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 16, trailing: 20))
    }

    // MARK: - Steps

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Everything stays on this Mac")
            Text("""
            Flightdeck has no account, no server and no upload. It does not sit between \
            you and Anthropic. Here is exactly what it touches:
            """)
            .font(Theme.ui(12.5))
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)

            factRow("doc.text.magnifyingglass", "Reads",
                    "~/.claude/projects — your session transcripts, for cost, tokens and context")
            factRow("gearshape", "Reads",
                    "~/.claude.json — plan limits, per-project totals and skill usage")
            factRow("arrow.triangle.branch", "Runs",
                    "git, read-only, in your repos — to measure how much of Claude's code survived")
            factRow("square.and.pencil", "Writes",
                    "~/.claude/settings.json — only if you install the integration, and always after a timestamped backup",
                    accent: Theme.warning)
        }
    }

    private var integrationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Connect live telemetry")
            Text("""
            Transcripts already give you history with no setup. Claude Code's statusline \
            and hooks add what transcripts never record: the real context-window size, \
            running cost as it changes, and tool events the moment they happen.
            """)
            .font(Theme.ui(12.5))
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)

            if let installStatus, installStatus.isFullyInstalled {
                calloutRow("checkmark.circle.fill", Theme.good,
                           "Already connected. Nothing to do.")
            } else if let installStatus, installStatus.hasStatuslineConflict {
                calloutRow("exclamationmark.triangle.fill", Theme.warning,
                           "You already have your own statusline. Flightdeck will not replace it — the hooks still install, but live context and cost stay unavailable.")
            } else {
                calloutRow("bolt.horizontal.circle", Theme.accent,
                           "Not connected yet. Without this, context size is inferred and cost updates lag until a session ends.")
            }

            HStack(spacing: 10) {
                Button("Install integration") { install() }
                    .font(Theme.ui(12, weight: .semibold))
                    .disabled(installStatus?.isFullyInstalled == true)
                Button("Reveal settings.json") {
                    NSWorkspace.shared.activateFileViewerSelecting([settingsURL])
                }
                .font(Theme.ui(12))
            }

            if !installNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(installNotes, id: \.self) { note in
                        Text("· \(note)")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.ink2)
                    }
                }
            }
            if let installError {
                Text(installError)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.critical)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("You can do this later from Claude Code → Sessions → Set up.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.ink3)
        }
    }

    private var tourStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Where things are")
            factRow("gauge.with.needle", "Cockpit  ⌘1", "Everything at a glance")
            factRow("bubble.left.and.bubble.right.fill", "Claude Code  ⌘2",
                    "Sessions, what your spend produced, and MCP servers")
            factRow("waveform.path.ecg", "System  ⌘3", "Vitals, processes and listening ports")
            factRow("folder.fill", "Storage  ⌘4", "Disk space, duplicates, apps and build cruft")
            factRow("dollarsign.circle", "Spend  ⌘5", "Cost by project")

            calloutRow("bell.fill", Theme.accent,
                       "Flightdeck will warn you before a five-hour limit, your daily budget or a context window runs out. Turn alerts off any time from the menu bar.")
        }
    }

    // MARK: - Pieces

    private func stepTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.display(16, weight: .semibold))
            .foregroundStyle(Theme.ink1)
    }

    private func factRow(_ icon: String, _ label: String, _ detail: String,
                         accent: Color = Theme.accent) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.ink1)
                Text(detail)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private func calloutRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(text)
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.22), lineWidth: 1))
    }

    // MARK: - Actions

    private func refreshStatus() {
        switch ClaudeIntegrationInstaller.readSettings(from: settingsURL) {
        case .missing:
            installStatus = ClaudeIntegrationInstaller.status(in: [:])
        case .parsed(let settings):
            installStatus = ClaudeIntegrationInstaller.status(in: settings)
        case .unreadable(let reason):
            installStatus = nil
            installError = "Can't read \(settingsURL.path): \(reason)"
        }
    }

    private func install() {
        installError = nil
        installNotes = []

        let settings: [String: Any]
        switch ClaudeIntegrationInstaller.readSettings(from: settingsURL) {
        case .missing:
            settings = [:]
        case .parsed(let existing):
            settings = existing
        case .unreadable(let reason):
            // Never write over a file we could not parse — it still holds the
            // user's real configuration.
            installError = "Can't read \(settingsURL.path): \(reason)\n\nNothing was changed."
            return
        }

        let baseline = ClaudeIntegrationInstaller.currentBytes(of: settingsURL)
        let binaryPath = ClaudeIntegrationInstaller.installCLIBinary()
        let change = ClaudeIntegrationInstaller.applyInstall(to: settings, binaryPath: binaryPath)
        installNotes = change.notes

        if change.didChange {
            do {
                if let backup = try ClaudeIntegrationInstaller.write(
                    change.settings, to: settingsURL, expecting: baseline
                ) {
                    installNotes.append("Backed up your previous settings to \(backup.lastPathComponent)")
                }
            } catch {
                installError = "Couldn't write \(settingsURL.path): \(error.localizedDescription)"
            }
        }
        refreshStatus()
    }

    private func finish() {
        Self.markSeen()
        dismiss()
    }
}
