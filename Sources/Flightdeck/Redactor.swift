import Foundation

/// Replaces the parts of the UI that identify *what you are working on*, so the
/// window is safe to screenshare, screenshot or demo.
///
/// Project directories, session titles (which are derived from your own first
/// prompt), branch names, paths and file names all name client work. Spend,
/// tokens, survival and every other measurement are deliberately left alone —
/// masking those would make a shared screen a lie, which is the opposite of
/// the point. There is no API here that takes a number.
struct Redactor: Equatable, Sendable {
    var isEnabled: Bool

    /// Real project name to neutral label. Assigned in sorted order so the same
    /// project keeps the same label across relaunches and between screenshots.
    private var labels: [String: String] = [:]

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    // MARK: - Registration

    mutating func register(projects: [String]) {
        let unique = Set(projects.filter { !$0.isEmpty }).sorted()
        labels = Dictionary(
            uniqueKeysWithValues: unique.enumerated().map { index, name in
                (name, "project-\(Self.letter(for: index))")
            }
        )
    }

    /// a, b, … z, aa, ab — so the scheme does not run out or start colliding.
    private static func letter(for index: Int) -> String {
        let alphabet = "abcdefghijklmnopqrstuvwxyz"
        guard index >= alphabet.count else {
            return String(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
        }
        let first = letter(for: index / alphabet.count - 1)
        let second = letter(for: index % alphabet.count)
        return first + second
    }

    // MARK: - Masking

    func project(_ name: String) -> String {
        guard isEnabled, !name.isEmpty else { return name }
        if let label = labels[name] { return label }
        // Never fall through to the real name: a project discovered after the
        // last registration would otherwise leak.
        return "project-\(Self.stableSuffix(of: name))"
    }

    /// Titles come from the user's opening prompt, so there is nothing in one
    /// worth preserving. Rebuilt from the project label instead.
    func title(_ title: String, project: String) -> String {
        guard isEnabled, !title.isEmpty else { return title }
        return "\(self.project(project)) session"
    }

    /// Keeps the prefix, because `feat/` vs `bugfix/` says something real about the
    /// work without naming it.
    func branch(_ branch: String) -> String {
        guard isEnabled, !branch.isEmpty else { return branch }
        if branch == "HEAD" || branch == "main" || branch == "master" { return branch }
        guard let slash = branch.firstIndex(of: "/") else { return "branch" }
        return branch[branch.startIndex..<slash] + "/branch"
    }

    func path(_ path: String) -> String {
        guard isEnabled, !path.isEmpty else { return path }
        let name = (path as NSString).lastPathComponent
        return "~/\(projectSegment(in: path))/\(fileName(name))"
    }

    /// The extension is real signal — a session writing `.swift` is doing
    /// something different from one writing `.md` — so it survives.
    ///
    /// The stem becomes a short stable token rather than a constant: three
    /// different `.py` files all rendering as `file.py` turned a churn list
    /// into the same row three times.
    func fileName(_ name: String) -> String {
        guard isEnabled, !name.isEmpty else { return name }
        let ext = (name as NSString).pathExtension
        let token = Self.stableSuffix(of: name)
        return ext.isEmpty ? "file-\(token)" : "\(token).\(ext)"
    }

    /// Standard home folders name nothing about you, and masking them would
    /// make the file browser unreadable for no privacy gain.
    private static let neutralFolders: Set<String> = [
        "Downloads", "Desktop", "Documents", "Applications", "Movies", "Music",
        "Pictures", "Public", "Library", "Developer", "Users", "Projects",
    ]

    /// The account name sits in every absolute path and identifies you directly.
    func userName(_ component: String) -> String {
        guard isEnabled, !component.isEmpty else { return component }
        return component == NSUserName() ? "you" : component
    }

    func homeRelative(_ path: String) -> String {
        guard isEnabled, !path.isEmpty else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// A file browser row. Folders everyone has keep their names; everything
    /// else keeps only its extension.
    func entryName(_ name: String) -> String {
        guard isEnabled, !name.isEmpty else { return name }
        if Self.neutralFolders.contains(name) || name == NSUserName() {
            return name == NSUserName() ? "you" : name
        }
        return fileName(name)
    }

    func hostname(_ name: String) -> String {
        guard isEnabled, !name.isEmpty else { return name }
        return "this-mac"
    }

    func sessionID(_ id: String) -> String {
        guard isEnabled, !id.isEmpty else { return id }
        return "sess-\(Self.stableSuffix(of: id))"
    }

    // MARK: - Helpers

    /// Finds a registered project name inside a path so the path's own label
    /// matches the one shown elsewhere for the same project.
    private func projectSegment(in path: String) -> String {
        for (real, label) in labels where path.contains(real) { return label }
        return "project"
    }

    /// A short, stable, non-reversible suffix. Not security — just enough that
    /// two different unregistered values do not render identically.
    private static func stableSuffix(of value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = (hash << 5) &+ hash &+ UInt64(byte)
        }
        return String(hash % 46_656, radix: 36)
    }
}
