import AppKit
import Foundation

/// Whether an item can actually be deleted — decided *before* the button is
/// drawn.
///
/// Offering a Delete button that is going to fail, then reporting the failure
/// afterwards, is backwards. The app knows in advance which permission is
/// missing and where it's granted, so it should say so up front and not ask
/// for a confirmation it can't honour.
enum FileGuard: Equatable, Sendable {
    /// Safe to move to Trash.
    case allowed
    /// System Integrity Protection. Not even root can delete these.
    case systemProtected
    /// The sealed system volume, or a disk image / network share mounted
    /// read-only.
    case readOnlyVolume
    /// Someone set the locked flag in Finder, or it's system-immutable.
    case locked
    /// A TCC-protected location — Mail, Messages, Safari, the Photos library.
    /// Readable only with Full Disk Access, which macOS grants nowhere but
    /// System Settings.
    case needsFullDiskAccess
    /// The containing folder isn't writable by this user.
    case notWritable

    var isAllowed: Bool { self == .allowed }

    /// Short enough to sit in a row without pushing the layout around.
    var badge: String {
        switch self {
        case .allowed:             return ""
        case .systemProtected:     return "SIP"
        case .readOnlyVolume:      return "READ-ONLY"
        case .locked:              return "LOCKED"
        case .needsFullDiskAccess: return "NEEDS FDA"
        case .notWritable:         return "NO WRITE"
        }
    }

    var symbol: String {
        switch self {
        case .allowed:             return "trash"
        case .systemProtected:     return "shield.lefthalf.filled"
        case .readOnlyVolume:      return "externaldrive.badge.xmark"
        case .locked:              return "lock.fill"
        case .needsFullDiskAccess: return "lock.shield"
        case .notWritable:         return "hand.raised.fill"
        }
    }

    /// The sentence a person can act on. No "operation could not be
    /// completed" — say which permission, and what to do about it.
    var explanation: String {
        switch self {
        case .allowed:
            return ""
        case .systemProtected:
            return "System Integrity Protection owns this. macOS blocks deletion here even for an administrator — there is nothing to grant."
        case .readOnlyVolume:
            return "This volume is mounted read-only, so nothing on it can be changed."
        case .locked:
            return "This item is locked. Unlock it in Finder's Get Info panel first."
        case .needsFullDiskAccess:
            return "This is a privacy-protected location. Flightdeck needs Full Disk Access, which macOS only lets you grant in System Settings."
        case .notWritable:
            return "The enclosing folder isn't writable by your account, so its contents can't be removed."
        }
    }

    /// Whether there's a settings pane worth opening. `.systemProtected` and
    /// `.readOnlyVolume` deliberately have none — pretending otherwise sends
    /// someone hunting for a switch that doesn't exist.
    var settingsFix: Bool {
        self == .needsFullDiskAccess
    }
}

// MARK: - Evaluation

extension FileGuard {
    /// Paths macOS protects with SIP. `/usr/local` is the documented carve-out,
    /// which is why the check is a prefix match with one exception rather than
    /// a blanket `/usr`.
    private static let protectedPrefixes = [
        "/System", "/bin", "/sbin", "/usr", "/Library/Apple",
        "/private/var/db/ConfigurationProfiles",
    ]
    private static let protectedExceptions = ["/usr/local"]

    /// TCC-guarded locations, relative to home. Readable only with Full Disk
    /// Access.
    private static let privacyPrefixes = [
        "Library/Mail", "Library/Messages", "Library/Safari", "Library/Cookies",
        "Library/Application Support/com.apple.TCC", "Library/Suggestions",
        "Library/Metadata/CoreSpotlight", "Library/HomeKit", "Library/IdentityServices",
        "Library/Sharing", "Library/Calendars", "Library/Accounts", "Library/Reminders",
        "Pictures/Photos Library.photoslibrary",
    ]

    /// Checks run most-absolute first: something under SIP is unfixable no
    /// matter what the file's own permission bits say, so reporting "no write
    /// permission" there would be technically true and completely unhelpful.
    static func evaluate(_ url: URL, hasFullDiskAccess: Bool) -> FileGuard {
        let path = url.path

        if isSystemProtected(path) { return .systemProtected }

        let values = try? url.resourceValues(forKeys: [
            .volumeIsReadOnlyKey, .isUserImmutableKey, .isSystemImmutableKey,
        ])
        if values?.volumeIsReadOnly == true { return .readOnlyVolume }
        if values?.isUserImmutable == true || values?.isSystemImmutable == true { return .locked }

        if !hasFullDiskAccess, isPrivacyProtected(path) { return .needsFullDiskAccess }

        // Last, because it's the check most likely to be a red herring when one
        // of the above already applies.
        guard FileManager.default.isDeletableFile(atPath: path) else { return .notWritable }
        return .allowed
    }

    static func isSystemProtected(_ path: String) -> Bool {
        if protectedExceptions.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return false
        }
        return protectedPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func isPrivacyProtected(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home + "/") else { return false }
        let relative = String(path.dropFirst(home.count + 1))
        return privacyPrefixes.contains { relative == $0 || relative.hasPrefix($0 + "/") }
    }

    /// FDA has no programmatic prompt — the only honest move is to open the
    /// exact pane and let the user grant it.
    static func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - Deleting, with a way back

/// What was moved, and where it landed — so "Undo" can be a real move back
/// rather than a hopeful re-download.
struct TrashReceipt: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let originalURL: URL
    let trashURL: URL?
    let bytes: Int64
    let isDirectory: Bool

    var canUndo: Bool { trashURL != nil }
}

enum TrashOutcome: Sendable {
    case moved(TrashReceipt)
    /// Refused before touching anything, with the reason.
    case blocked(FileGuard)
    case failed(String)
}

enum TrashService {
    /// Moves to Trash rather than unlinking. Recoverable by default is the
    /// right behaviour for a delete button someone might hit by accident, and
    /// it's what makes the undo below possible at all.
    static func trash(
        _ url: URL,
        name: String,
        bytes: Int64,
        isDirectory: Bool,
        hasFullDiskAccess: Bool
    ) -> TrashOutcome {
        let verdict = FileGuard.evaluate(url, hasFullDiskAccess: hasFullDiskAccess)
        guard verdict.isAllowed else { return .blocked(verdict) }

        var landed: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
        } catch {
            return .failed((error as NSError).localizedDescription)
        }

        return .moved(
            TrashReceipt(
                name: name,
                originalURL: url,
                trashURL: landed as URL?,
                bytes: bytes,
                isDirectory: isDirectory
            )
        )
    }

    /// Puts it back where it came from.
    static func restore(_ receipt: TrashReceipt) -> String? {
        guard let trashURL = receipt.trashURL else {
            return "macOS didn't report where \(receipt.name) landed in the Trash."
        }
        guard !FileManager.default.fileExists(atPath: receipt.originalURL.path) else {
            return "Something already exists at \(receipt.originalURL.lastPathComponent)."
        }
        do {
            try FileManager.default.moveItem(at: trashURL, to: receipt.originalURL)
            return nil
        } catch {
            return (error as NSError).localizedDescription
        }
    }
}
