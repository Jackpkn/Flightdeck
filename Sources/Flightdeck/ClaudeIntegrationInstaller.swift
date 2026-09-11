import Foundation

/// Installs and removes Flightdeck's entries in `~/.claude/settings.json`.
///
/// Two channels feed the live session data: Claude Code's statusline (context window
/// and running cost, every couple of seconds) and its hooks (tool use, session start
/// and stop). Without them Flightdeck only sees what transcripts happen to record.
///
/// Every mutation here is a pure function on the settings dictionary so it can be
/// tested without touching a real config, and the file is backed up before any write —
/// this is the user's own Claude Code configuration, not ours.
enum ClaudeIntegrationInstaller {

    /// Subcommands Flightdeck's CLI exposes. An entry counts as ours only if it both
    /// names a flightdeck binary *and* invokes one of these — a bare "flightdeck"
    /// substring also matched a user hook that merely `cd`s into a folder of that
    /// name, which uninstall would then have deleted.
    static let subcommands = ["statusline", "hook"]
    static let marker = "flightdeck"

    static func isFlightdeckCommand(_ command: String?) -> Bool {
        guard let command else { return false }
        let lower = command.lowercased()
        guard lower.contains(marker) else { return false }
        // The binary is always the first token, and the subcommand immediately follows.
        let tokens = lower.split(separator: " ").map(String.init)
        guard let binaryIndex = tokens.firstIndex(where: { $0.contains(marker) }),
              tokens.indices.contains(binaryIndex + 1) else { return false }
        return subcommands.contains(tokens[binaryIndex + 1])
    }

    /// Claude Code hook events Flightdeck subscribes to, with why.
    static let requiredHooks: [(event: String, description: String)] = [
        ("PostToolUse", "Flightdeck: track tool use in activity feed"),
        ("SessionStart", "Flightdeck: record session start"),
        ("Stop", "Flightdeck: record session stop / cost update"),
    ]

    // MARK: - Status

    struct Status: Equatable {
        var statuslineInstalled: Bool
        /// A statusline from something else is already configured — Flightdeck must
        /// not replace it, so the live context/cost channel stays unavailable.
        var hasStatuslineConflict: Bool
        var installedHooks: Set<String>

        var missingHooks: [String] {
            requiredHooks.map(\.event).filter { !installedHooks.contains($0) }
        }

        var isFullyInstalled: Bool {
            statuslineInstalled && missingHooks.isEmpty
        }
    }

    static func status(in settings: [String: Any]) -> Status {
        let statusLine = unwrap(settings["statusLine"]) as? [String: Any]
        let isOurs = isFlightdeckCommand(statusLine?["command"] as? String)

        var installed: Set<String> = []
        let hooks = unwrap(settings["hooks"]) as? [String: Any] ?? [:]
        for (event, _) in requiredHooks where containsFlightdeckHook(hooks[event]) {
            installed.insert(event)
        }

        return Status(
            statuslineInstalled: isOurs,
            hasStatuslineConflict: statusLine != nil && !isOurs,
            installedHooks: installed
        )
    }

    // MARK: - Install

    struct Change {
        var settings: [String: Any]
        var didChange: Bool
        /// Human-readable log of what was done, shown in the setup sheet.
        var notes: [String]
    }

    static func applyInstall(to settings: [String: Any], binaryPath: String) -> Change {
        var out = settings
        var notes: [String] = []
        var changed = false

        let current = status(in: settings)

        // 1. Statusline — the only source of live context-window size and running cost.
        if current.statuslineInstalled {
            notes.append("Statusline already configured")
        } else if current.hasStatuslineConflict {
            notes.append("Left your existing statusline untouched — live context and cost stay unavailable")
        } else {
            out["statusLine"] = [
                "type": "command",
                "command": "\(binaryPath) statusline",
                "padding": 0,
            ] as [String: Any]
            notes.append("Added statusline")
            changed = true
        }

        // 2. Hooks — appended alongside whatever else is registered for the event.
        var hooks = unwrap(out["hooks"]) as? [String: Any] ?? [:]
        for required in requiredHooks {
            if current.installedHooks.contains(required.event) {
                notes.append("\(required.event) hook already installed")
                continue
            }
            var eventHooks = unwrap(hooks[required.event]) as? [[String: Any]] ?? []
            eventHooks.append([
                "matcher": "*",
                "hooks": [[
                    "type": "command",
                    "command": "\(binaryPath) hook \(required.event.lowercased())",
                    "async": true,
                    "timeout": 5,
                ] as [String: Any]],
                "description": required.description,
            ] as [String: Any])
            hooks[required.event] = eventHooks
            notes.append("Added \(required.event) hook")
            changed = true
        }
        if changed { out["hooks"] = hooks }

        return Change(settings: out, didChange: changed, notes: notes)
    }

    // MARK: - Uninstall

    static func applyUninstall(to settings: [String: Any]) -> Change {
        var out = settings
        var notes: [String] = []
        var changed = false

        if status(in: settings).statuslineInstalled {
            out.removeValue(forKey: "statusLine")
            notes.append("Removed statusline")
            changed = true
        }

        if var hooks = unwrap(out["hooks"]) as? [String: Any] {
            for (event, _) in requiredHooks {
                guard var eventHooks = unwrap(hooks[event]) as? [[String: Any]] else { continue }
                let before = eventHooks.count
                eventHooks.removeAll { isFlightdeckEntry($0) }
                guard eventHooks.count != before else { continue }
                // Drop the event key entirely when we were its only subscriber, so
                // uninstalling leaves the file exactly as it was found.
                if eventHooks.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = eventHooks
                }
                notes.append("Removed \(event) hook")
                changed = true
            }
            if changed {
                if hooks.isEmpty {
                    out.removeValue(forKey: "hooks")
                } else {
                    out["hooks"] = hooks
                }
            }
        }

        return Change(settings: out, didChange: changed, notes: notes)
    }

    // MARK: - Disk

    static func defaultSettingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// Outcome of reading the user's settings file.
    ///
    /// The distinction matters: a file that is absent can safely be created, but a
    /// file that exists and merely failed to parse — mid-write by Claude Code, or
    /// hand-edited with a trailing comma — still holds the user's real configuration.
    /// Treating that as empty and writing would erase all of it.
    enum SettingsRead: Equatable {
        case missing
        case parsed([String: Any])
        case unreadable(String)

        static func == (lhs: SettingsRead, rhs: SettingsRead) -> Bool {
            switch (lhs, rhs) {
            case (.missing, .missing): return true
            case (.unreadable, .unreadable): return true
            case (.parsed(let l), .parsed(let r)): return NSDictionary(dictionary: l) == NSDictionary(dictionary: r)
            default: return false
            }
        }
    }

    enum WriteError: LocalizedError {
        case changedOnDisk

        var errorDescription: String? {
            switch self {
            case .changedOnDisk:
                return "settings.json changed on disk while Flightdeck was editing it. Nothing was written — reopen setup and try again."
            }
        }
    }

    static func readSettings(from url: URL) -> SettingsRead {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unreadable(error.localizedDescription)
        }
        // An empty file is effectively an absent one — safe to populate.
        if data.isEmpty { return .missing }
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unreadable("settings.json does not contain a JSON object at its top level.")
            }
            return .parsed(parsed)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    /// Raw bytes of the settings file as read, used to detect a concurrent edit
    /// before overwriting. Nil when there is no file yet.
    static func currentBytes(of url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    /// Writes settings back, first copying the existing file to a timestamped backup.
    /// Returns the backup URL, or nil when there was no file to back up.
    ///
    /// `expecting` is the file's contents at the time it was read. If the bytes on
    /// disk no longer match, someone else edited the file in between and the write is
    /// refused rather than silently discarding their change.
    @discardableResult
    static func write(_ settings: [String: Any], to url: URL, expecting: Data? = nil) throws -> URL? {
        if let expecting {
            let now = currentBytes(of: url)
            guard now == expecting else { throw WriteError.changedOnDisk }
        }

        var backupURL: URL?
        if FileManager.default.fileExists(atPath: url.path) {
            let stamp = ISO8601DateFormatter.backupStamp.string(from: Date())
                .replacingOccurrences(of: ":", with: "")
            let candidate = url.deletingPathExtension()
                .appendingPathExtension("flightdeck-backup-\(stamp).json")
            try? FileManager.default.removeItem(at: candidate)
            try FileManager.default.copyItem(at: url, to: candidate)
            backupURL = candidate
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
        return backupURL
    }

    /// Copies the running binary to a stable location so the hook commands survive the
    /// app bundle moving, and returns the path to reference from settings.
    static func installCLIBinary() -> String {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Flightdeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let target = appSupport.appendingPathComponent("flightdeck-cli").path

        let current = ProcessInfo.processInfo.arguments.first ?? ""
        if !current.isEmpty, current != target {
            try? FileManager.default.removeItem(atPath: target)
            try? FileManager.default.copyItem(atPath: current, toPath: target)
        }
        return FileManager.default.fileExists(atPath: target) ? target : current
    }

    // MARK: - Helpers

    /// JSON `null` decodes to `NSNull`, not `nil`. Treating `"statusLine": null` as
    /// "already configured" is why the statusline silently never installed.
    private static func unwrap(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        return value
    }

    private static func containsFlightdeckHook(_ raw: Any?) -> Bool {
        guard let entries = unwrap(raw) as? [[String: Any]] else { return false }
        return entries.contains(where: isFlightdeckEntry)
    }

    private static func isFlightdeckEntry(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { isFlightdeckCommand($0["command"] as? String) }
    }
}

private extension ISO8601DateFormatter {
    /// Stamp for backup filenames. Colons are stripped by the caller — they are legal
    /// on APFS but show up as `/` in Finder and need quoting in a shell.
    static let backupStamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}
