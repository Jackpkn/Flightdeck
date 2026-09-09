import Foundation
import Testing
@testable import Flightdeck

struct FileBrowserTests {
    @Test("FileBrowser filteredEntries filters by search query and categories")
    func testFiltering() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flightdeck-browser-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("SubFolder")
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)

        let codeFile = tempDir.appendingPathComponent("server.swift")
        try "print(1)".write(to: codeFile, atomically: true, encoding: .utf8)

        let docFile = tempDir.appendingPathComponent("notes.md")
        try "# Notes".write(to: docFile, atomically: true, encoding: .utf8)

        let imgFile = tempDir.appendingPathComponent("avatar.png")
        try Data([1, 2, 3]).write(to: imgFile)

        let browser = FileBrowser(start: tempDir)
        browser.start()

        #expect(browser.entries.count == 4)

        // Test search query
        browser.searchQuery = "server"
        #expect(browser.filteredEntries.count == 1)
        #expect(browser.filteredEntries.first?.name == "server.swift")

        browser.searchQuery = "md"
        #expect(browser.filteredEntries.count == 1)
        #expect(browser.filteredEntries.first?.name == "notes.md")

        browser.searchQuery = ""

        // Test only folders
        browser.onlyFolders = true
        #expect(browser.filteredEntries.count == 1)
        #expect(browser.filteredEntries.first?.name == "SubFolder")
        browser.onlyFolders = false

        // Test category filter
        browser.categoryFilter = .image
        #expect(browser.filteredEntries.count == 1)
        #expect(browser.filteredEntries.first?.name == "avatar.png")

        browser.categoryFilter = nil
        #expect(browser.filteredEntries.count == 4)
    }

    @Test("FileBrowser retrieves volume telemetry and Git branch when present")
    func testVolumeTelemetryAndGit() throws {
        // Point browser at workspace repository
        let currentRepoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let browser = FileBrowser(start: currentRepoURL)
        browser.start()

        #expect(browser.volumeTotalBytes > 0)
        #expect(browser.volumeFreeBytes > 0)
        #expect(browser.volumeUsageRatio > 0 && browser.volumeUsageRatio <= 1.0)
        #expect(browser.totalFilteredBytes >= 0)

        // Workspace is a git repository
        if FileManager.default.fileExists(atPath: currentRepoURL.appendingPathComponent(".git").path) {
            #expect(browser.currentGitBranch != nil)
        }
    }
}

