import Testing
import Foundation
@testable import Flightdeck

@Suite("Claude integration installer")
struct ClaudeIntegrationInstallerTests {

    private let binary = "/Users/test/Library/Application Support/Flightdeck/flightdeck-cli"

    // MARK: - Status inspection

    @Test("Empty settings report nothing installed")
    func emptySettings() {
        let status = ClaudeIntegrationInstaller.status(in: [:])
        #expect(!status.statuslineInstalled)
        #expect(!status.hasStatuslineConflict)
        #expect(status.installedHooks.isEmpty)
        #expect(!status.isFullyInstalled)
        #expect(status.missingHooks.count == ClaudeIntegrationInstaller.requiredHooks.count)
    }

    /// JSONSerialization turns a JSON `null` into `NSNull`, not `nil`, so a
    /// `settings["statusLine"] == nil` check silently treats `"statusLine": null`
    /// as already-configured and never installs. That is the state real
    /// `~/.claude/settings.json` files are in.
    @Test("An explicit null statusLine counts as not installed")
    func nullStatuslineIsNotInstalled() {
        let settings: [String: Any] = ["statusLine": NSNull()]
        let status = ClaudeIntegrationInstaller.status(in: settings)
        #expect(!status.statuslineInstalled)
        #expect(!status.hasStatuslineConflict)
    }

    @Test("A Flightdeck statusline is recognised as installed")
    func recognisesOwnStatusline() {
        let settings: [String: Any] = [
            "statusLine": ["type": "command", "command": "\(binary) statusline"]
        ]
        let status = ClaudeIntegrationInstaller.status(in: settings)
        #expect(status.statuslineInstalled)
        #expect(!status.hasStatuslineConflict)
    }

    @Test("Someone else's statusline is flagged as a conflict, not overwritten")
    func detectsForeignStatusline() {
        let settings: [String: Any] = [
            "statusLine": ["type": "command", "command": "/usr/local/bin/my-prompt"]
        ]
        let status = ClaudeIntegrationInstaller.status(in: settings)
        #expect(!status.statuslineInstalled)
        #expect(status.hasStatuslineConflict)
    }

    @Test("Existing Flightdeck hooks are detected per event")
    func detectsInstalledHooks() {
        let settings: [String: Any] = [
            "hooks": [
                "PostToolUse": [[
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "\(binary) hook posttooluse"]],
                ]]
            ]
        ]
        let status = ClaudeIntegrationInstaller.status(in: settings)
        #expect(status.installedHooks.contains("PostToolUse"))
        #expect(!status.installedHooks.contains("Stop"))
        #expect(status.missingHooks.contains("Stop"))
    }

    @Test("Unrelated hooks from other tools are not mistaken for ours")
    func ignoresForeignHooks() {
        let settings: [String: Any] = [
            "hooks": [
                "PostToolUse": [[
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "some-other-tool report"]],
                ]]
            ]
        ]
        let status = ClaudeIntegrationInstaller.status(in: settings)
        #expect(status.installedHooks.isEmpty)
    }

    // MARK: - Applying changes

    @Test("Install adds the statusline and every required hook")
    func installAddsEverything() throws {
        let result = ClaudeIntegrationInstaller.applyInstall(to: [:], binaryPath: binary)
        #expect(result.didChange)

        let status = ClaudeIntegrationInstaller.status(in: result.settings)
        #expect(status.isFullyInstalled)

        let statusLine = try #require(result.settings["statusLine"] as? [String: Any])
        #expect((statusLine["command"] as? String) == "\(binary) statusline")
    }

    @Test("Install is idempotent — running it twice changes nothing the second time")
    func installIsIdempotent() {
        let first = ClaudeIntegrationInstaller.applyInstall(to: [:], binaryPath: binary)
        let second = ClaudeIntegrationInstaller.applyInstall(to: first.settings, binaryPath: binary)
        #expect(!second.didChange)
    }

    @Test("Install replaces a null statusLine instead of skipping it")
    func installOverwritesNull() throws {
        let result = ClaudeIntegrationInstaller.applyInstall(to: ["statusLine": NSNull()], binaryPath: binary)
        #expect(result.didChange)
        let statusLine = try #require(result.settings["statusLine"] as? [String: Any])
        #expect((statusLine["command"] as? String)?.contains("flightdeck-cli") == true)
    }

    @Test("Install never clobbers a statusline the user already configured")
    func installPreservesForeignStatusline() throws {
        let settings: [String: Any] = [
            "statusLine": ["type": "command", "command": "/usr/local/bin/my-prompt"]
        ]
        let result = ClaudeIntegrationInstaller.applyInstall(to: settings, binaryPath: binary)
        let statusLine = try #require(result.settings["statusLine"] as? [String: Any])
        #expect((statusLine["command"] as? String) == "/usr/local/bin/my-prompt")
        // The hooks still go in — only the conflicting key is left alone.
        #expect(ClaudeIntegrationInstaller.status(in: result.settings).installedHooks.count
                == ClaudeIntegrationInstaller.requiredHooks.count)
    }

    @Test("Install leaves every unrelated setting untouched")
    func installPreservesOtherSettings() throws {
        let settings: [String: Any] = [
            "effortLevel": "xhigh",
            "env": ["MAX_THINKING_TOKENS": "10000"],
            "hooks": [
                "UserPromptSubmit": [[
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "other-tool run"]],
                ]]
            ],
        ]
        let result = ClaudeIntegrationInstaller.applyInstall(to: settings, binaryPath: binary)
        #expect((result.settings["effortLevel"] as? String) == "xhigh")
        let env = try #require(result.settings["env"] as? [String: Any])
        #expect((env["MAX_THINKING_TOKENS"] as? String) == "10000")

        let hooks = try #require(result.settings["hooks"] as? [String: Any])
        let foreign = try #require(hooks["UserPromptSubmit"] as? [[String: Any]])
        #expect(foreign.count == 1)
    }

    @Test("Install appends to an event that already has other tools' hooks")
    func installAppendsAlongsideOthers() throws {
        let settings: [String: Any] = [
            "hooks": [
                "PostToolUse": [[
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "other-tool report"]],
                ]]
            ]
        ]
        let result = ClaudeIntegrationInstaller.applyInstall(to: settings, binaryPath: binary)
        let hooks = try #require(result.settings["hooks"] as? [String: Any])
        let postToolUse = try #require(hooks["PostToolUse"] as? [[String: Any]])
        #expect(postToolUse.count == 2)
    }

    // MARK: - Uninstall

    @Test("Uninstall removes only Flightdeck's entries")
    func uninstallRemovesOnlyOurs() throws {
        var settings: [String: Any] = [
            "hooks": [
                "PostToolUse": [[
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "other-tool report"]],
                ]]
            ]
        ]
        settings = ClaudeIntegrationInstaller.applyInstall(to: settings, binaryPath: binary).settings
        let removed = ClaudeIntegrationInstaller.applyUninstall(to: settings)
        #expect(removed.didChange)

        let status = ClaudeIntegrationInstaller.status(in: removed.settings)
        #expect(!status.statuslineInstalled)
        #expect(status.installedHooks.isEmpty)

        let hooks = try #require(removed.settings["hooks"] as? [String: Any])
        let postToolUse = try #require(hooks["PostToolUse"] as? [[String: Any]])
        #expect(postToolUse.count == 1)
        let inner = try #require(postToolUse[0]["hooks"] as? [[String: Any]])
        #expect((inner[0]["command"] as? String) == "other-tool report")
    }

    @Test("Uninstalling when nothing is installed is a no-op")
    func uninstallNoOp() {
        let result = ClaudeIntegrationInstaller.applyUninstall(to: ["effortLevel": "xhigh"])
        #expect(!result.didChange)
    }

    @Test("Uninstall does not remove a statusline the user set themselves")
    func uninstallPreservesForeignStatusline() throws {
        let settings: [String: Any] = [
            "statusLine": ["type": "command", "command": "/usr/local/bin/my-prompt"]
        ]
        let result = ClaudeIntegrationInstaller.applyUninstall(to: settings)
        #expect(!result.didChange)
        let statusLine = try #require(result.settings["statusLine"] as? [String: Any])
        #expect((statusLine["command"] as? String) == "/usr/local/bin/my-prompt")
    }

    // MARK: - Round trip on disk

    @Test("Writing settings keeps a timestamped backup of the original")
    func writeMakesBackup() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fd-installer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let settingsURL = dir.appendingPathComponent("settings.json")
        let original = #"{"effortLevel":"xhigh"}"#
        try Data(original.utf8).write(to: settingsURL)

        let backup = try ClaudeIntegrationInstaller.write(
            ["effortLevel": "xhigh", "statusLine": ["type": "command", "command": "x"]],
            to: settingsURL
        )
        let backupURL = try #require(backup)
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        #expect(String(decoding: try Data(contentsOf: backupURL), as: UTF8.self) == original)

        // And the new content really landed.
        let reread = try JSONSerialization.jsonObject(with: try Data(contentsOf: settingsURL)) as? [String: Any]
        #expect(reread?["statusLine"] != nil)
    }

    @Test("Writing to a path with no existing file needs no backup")
    func writeWithoutExistingFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fd-installer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let settingsURL = dir.appendingPathComponent("settings.json")
        let backup = try ClaudeIntegrationInstaller.write(["a": 1], to: settingsURL)
        #expect(backup == nil)
        #expect(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    @Test("A full install/uninstall cycle restores the original settings exactly")
    func roundTripRestoresOriginal() throws {
        let original: [String: Any] = [
            "effortLevel": "xhigh",
            "hooks": ["UserPromptSubmit": [["matcher": "*", "hooks": [["type": "command", "command": "keep-me"]]]]],
        ]
        let installed = ClaudeIntegrationInstaller.applyInstall(to: original, binaryPath: binary).settings
        let restored = ClaudeIntegrationInstaller.applyUninstall(to: installed).settings

        #expect((restored["effortLevel"] as? String) == "xhigh")
        let hooks = try #require(restored["hooks"] as? [String: Any])
        #expect(hooks.count == 1)
        #expect(hooks["UserPromptSubmit"] != nil)
    }
}

@Suite("Settings read safety")
struct SettingsReadSafetyTests {

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fd-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("A missing settings file is reported as missing, not as empty settings")
    func missingFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = ClaudeIntegrationInstaller.readSettings(from: dir.appendingPathComponent("nope.json"))
        #expect(result == .missing)
    }

    @Test("A valid settings file parses")
    func validFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"effortLevel":"xhigh"}"#.utf8).write(to: url)
        guard case .parsed(let settings) = ClaudeIntegrationInstaller.readSettings(from: url) else {
            Issue.record("expected .parsed"); return
        }
        #expect((settings["effortLevel"] as? String) == "xhigh")
    }

    /// The dangerous case: the file exists and holds real settings, but can't be
    /// parsed right now (mid-write by Claude Code, hand-edited trailing comma).
    /// Treating that as "no settings" and writing would erase everything in it.
    @Test("An unparseable settings file is refused, never treated as empty")
    func unparseableFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"env": {"A": "1",} "#.utf8).write(to: url)

        let result = ClaudeIntegrationInstaller.readSettings(from: url)
        guard case .unreadable = result else {
            Issue.record("expected .unreadable, got \(result)"); return
        }
    }

    @Test("A JSON file whose root is not an object is refused")
    func nonObjectRoot() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data("[1,2,3]".utf8).write(to: url)
        guard case .unreadable = ClaudeIntegrationInstaller.readSettings(from: url) else {
            Issue.record("expected .unreadable"); return
        }
    }

    @Test("Writing refuses when the file changed since it was read")
    func refusesConcurrentModification() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"a":1}"#.utf8).write(to: url)

        let original = try Data(contentsOf: url)
        // Someone else edits the file between our read and our write.
        try Data(#"{"a":2,"b":3}"#.utf8).write(to: url)

        #expect(throws: ClaudeIntegrationInstaller.WriteError.self) {
            try ClaudeIntegrationInstaller.write(["a": 1], to: url, expecting: original)
        }
        // And the other party's edit survived untouched.
        let onDisk = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        #expect((onDisk?["b"] as? Int) == 3)
    }

    @Test("Writing succeeds when the file is unchanged since it was read")
    func writesWhenUnchanged() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"a":1}"#.utf8).write(to: url)
        let original = try Data(contentsOf: url)

        try ClaudeIntegrationInstaller.write(["a": 1, "b": 2], to: url, expecting: original)
        let onDisk = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        #expect((onDisk?["b"] as? Int) == 2)
    }
}

@Suite("Flightdeck entry identification")
struct FlightdeckEntryIdentificationTests {

    /// A bare "flightdeck" substring matched unrelated commands — a hook that merely
    /// cd's into a directory named flightdeck would have been deleted on uninstall.
    @Test("A user hook that only mentions a flightdeck path is not ours")
    func doesNotClaimUnrelatedCommands() {
        let settings: [String: Any] = [
            "hooks": [
                "PostToolUse": [[
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "cd ~/Projects/Flightdeck && make lint"]],
                ]]
            ],
            "statusLine": ["type": "command", "command": "~/Projects/flightdeck/prompt.sh"],
        ]
        let status = ClaudeIntegrationInstaller.status(in: settings)
        #expect(status.installedHooks.isEmpty)
        #expect(!status.statuslineInstalled)
        #expect(status.hasStatuslineConflict)

        // And uninstall leaves them alone.
        #expect(!ClaudeIntegrationInstaller.applyUninstall(to: settings).didChange)
    }

    @Test("Our own entries are still recognised")
    func claimsOwnCommands() {
        let binary = "/Users/x/Library/Application Support/Flightdeck/flightdeck-cli"
        let installed = ClaudeIntegrationInstaller.applyInstall(to: [:], binaryPath: binary).settings
        let status = ClaudeIntegrationInstaller.status(in: installed)
        #expect(status.isFullyInstalled)
    }

    @Test("An entry installed from the app bundle path is still recognised")
    func recognisesBundlePathInstall() {
        let binary = "/Applications/Flightdeck.app/Contents/MacOS/Flightdeck"
        let installed = ClaudeIntegrationInstaller.applyInstall(to: [:], binaryPath: binary).settings
        #expect(ClaudeIntegrationInstaller.status(in: installed).isFullyInstalled)
    }
}
