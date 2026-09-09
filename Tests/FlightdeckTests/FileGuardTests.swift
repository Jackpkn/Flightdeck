import Foundation
import Testing
@testable import Flightdeck

/// Permission logic has an asymmetric cost: refusing wrongly is annoying, but
/// *allowing* wrongly means a delete button that fails after the fact — the
/// exact behaviour this replaced. So the allow path is the one pinned down
/// hardest here.
struct FileGuardTests {
    // MARK: - Classification

    @Test("SIP paths are recognised, and /usr/local is the documented carve-out")
    func systemProtectedPaths() {
        #expect(FileGuard.isSystemProtected("/System"))
        #expect(FileGuard.isSystemProtected("/System/Library/CoreServices"))
        #expect(FileGuard.isSystemProtected("/bin/zsh"))
        #expect(FileGuard.isSystemProtected("/usr/lib/dyld"))
        #expect(FileGuard.isSystemProtected("/Library/Apple/System"))

        // /usr/local is writable by design — Homebrew lives there.
        #expect(!FileGuard.isSystemProtected("/usr/local"))
        #expect(!FileGuard.isSystemProtected("/usr/local/bin/brew"))
        // A prefix must not match a sibling that merely starts the same way.
        #expect(!FileGuard.isSystemProtected("/Systems"))
        #expect(!FileGuard.isSystemProtected("/binaries/thing"))
        #expect(!FileGuard.isSystemProtected("/Users/someone/Downloads/file.zip"))
    }

    @Test("Privacy-protected locations are recognised only inside this home folder")
    func privacyProtectedPaths() {
        let home = NSHomeDirectory()
        #expect(FileGuard.isPrivacyProtected(home + "/Library/Mail"))
        #expect(FileGuard.isPrivacyProtected(home + "/Library/Messages/chat.db"))
        #expect(FileGuard.isPrivacyProtected(home + "/Library/Safari/History.db"))
        #expect(FileGuard.isPrivacyProtected(home + "/Pictures/Photos Library.photoslibrary"))

        #expect(!FileGuard.isPrivacyProtected(home + "/Library/Caches"))
        #expect(!FileGuard.isPrivacyProtected(home + "/Downloads/mail.zip"))
        // Same suffix, different user — must not be claimed as ours.
        #expect(!FileGuard.isPrivacyProtected("/Users/someone-else/Library/Mail"))
        // A folder that merely starts with a protected name.
        #expect(!FileGuard.isPrivacyProtected(home + "/Library/Mailboxes-backup"))
    }

    @Test("A SIP path reports SIP, not a permission problem")
    func sipBeatsPermissionBits() {
        // Both are true of /System/Library, and only one of them is useful:
        // "no write permission" implies a fixable ownership issue.
        let verdict = FileGuard.evaluate(
            URL(fileURLWithPath: "/System/Library"),
            hasFullDiskAccess: true
        )
        #expect(verdict == .systemProtected)
        #expect(!verdict.settingsFix, "There is no setting that unlocks SIP")
    }

    @Test("Full Disk Access is only claimed as the fix when it actually is one")
    func onlyFDAOffersSettings() {
        for verdict in [FileGuard.systemProtected, .readOnlyVolume, .locked, .notWritable, .allowed] {
            #expect(!verdict.settingsFix, "\(verdict) must not send anyone to Settings")
        }
        #expect(FileGuard.needsFullDiskAccess.settingsFix)
    }

    @Test("Every refusal carries a reason and a distinct badge")
    func everyRefusalIsExplained() {
        let refusals: [FileGuard] = [
            .systemProtected, .readOnlyVolume, .locked, .needsFullDiskAccess, .notWritable,
        ]
        for verdict in refusals {
            #expect(!verdict.explanation.isEmpty, "\(verdict) has no explanation")
            #expect(!verdict.badge.isEmpty, "\(verdict) has no badge")
            #expect(verdict.symbol != "trash", "\(verdict) must not look like a working bin")
        }
        #expect(Set(refusals.map(\.badge)).count == refusals.count, "badges must be distinguishable")
        #expect(FileGuard.allowed.symbol == "trash")
    }

    @Test("A writable file in a writable folder is allowed")
    func writableFileIsAllowed() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flightdeck-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("ordinary.txt")
        try Data("hello".utf8).write(to: file)

        #expect(FileGuard.evaluate(file, hasFullDiskAccess: true) == .allowed)
    }

    @Test("A locked file is refused as locked, not deleted")
    func lockedFileIsRefused() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flightdeck-locked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("locked.txt")
        try Data("hello".utf8).write(to: file)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path)
            try? FileManager.default.removeItem(at: dir)
        }

        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path)
        #expect(FileGuard.evaluate(file, hasFullDiskAccess: true) == .locked)

        // And the delete must refuse *before* touching it.
        let outcome = TrashService.trash(
            file, name: "locked.txt", bytes: 5, isDirectory: false, hasFullDiskAccess: true
        )
        guard case let .blocked(verdict) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(verdict == .locked)
        #expect(FileManager.default.fileExists(atPath: file.path), "the file must still be there")
    }

    @Test("A file inside a non-writable folder is refused, and survives")
    func unwritableParentIsRefused() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flightdeck-ro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("stuck.txt")
        try Data("hello".utf8).write(to: file)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        // Deletion needs write permission on the *containing folder*, not the
        // file — a distinction that's easy to get backwards.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        #expect(FileGuard.evaluate(file, hasFullDiskAccess: true) == .notWritable)
        let outcome = TrashService.trash(
            file, name: "stuck.txt", bytes: 5, isDirectory: false, hasFullDiskAccess: true
        )
        guard case .blocked = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Delete and undo

    @Test("A delete reports where it landed, and undo puts it back byte-for-byte")
    func deleteIsReversible() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flightdeck-undo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("recoverable.bin")
        let payload = Data(repeating: 0x42, count: 4096)
        try payload.write(to: file)

        let outcome = TrashService.trash(
            file, name: "recoverable.bin", bytes: 4096, isDirectory: false, hasFullDiskAccess: true
        )
        guard case let .moved(receipt) = outcome else {
            Issue.record("expected a move, got \(outcome)")
            return
        }

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(receipt.canUndo, "without a trash URL there is no undo to offer")

        #expect(TrashService.restore(receipt) == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: file) == payload, "contents must survive the round trip")
    }

    @Test("Undo refuses to overwrite something that took the original name")
    func undoWontClobber() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flightdeck-clobber-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("contested.txt")
        try Data("original".utf8).write(to: file)

        guard case let .moved(receipt) = TrashService.trash(
            file, name: "contested.txt", bytes: 8, isDirectory: false, hasFullDiskAccess: true
        ) else {
            Issue.record("expected a move")
            return
        }

        // Someone put a different file at that name in the meantime.
        try Data("replacement".utf8).write(to: file)

        #expect(TrashService.restore(receipt) != nil, "undo must refuse rather than overwrite")
        #expect(try Data(contentsOf: file) == Data("replacement".utf8))
    }
}
