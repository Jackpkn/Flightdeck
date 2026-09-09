import AppKit
import Foundation

enum DevEditor: String, CaseIterable, Identifiable, Sendable {
    case vscode = "VS Code"
    case cursor = "Cursor"
    case xcode = "Xcode"
    case zed = "Zed"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .vscode: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .xcode:  return "hammer.fill"
        case .zed:    return "bolt.fill"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .xcode:  return "com.apple.dt.Xcode"
        case .zed:    return "dev.zed.Zed"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

enum DevAppLauncher {
    static var availableEditors: [DevEditor] {
        DevEditor.allCases.filter(\.isInstalled)
    }

    static var defaultEditor: DevEditor? {
        availableEditors.first
    }

    static func openInTerminal(_ url: URL) {
        let path = (url.hasDirectoryPath ? url : url.deletingLastPathComponent()).path
        // If iTerm is installed and preferred, use it; otherwise standard Terminal
        if let iTerm = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: iTerm, configuration: config) { _, error in
                if error != nil {
                    fallbackOpenTerminal(path)
                }
            }
        } else {
            fallbackOpenTerminal(path)
        }
    }

    private static func fallbackOpenTerminal(_ path: String) {
        if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal, configuration: config)
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Terminal", path]
            try? process.run()
        }
    }

    static func openInEditor(_ url: URL, editor: DevEditor? = nil) {
        guard let targetEditor = editor ?? defaultEditor,
              let appURL = targetEditor.appURL else {
            NSWorkspace.shared.open(url)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
    }

    static func openQuickLook(_ url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        task.arguments = ["-p", url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    static func openInDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func openSystemActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Activity Monitor"]
            try? process.run()
        }
    }
}
