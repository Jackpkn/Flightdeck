import Testing
import Foundation
@testable import Flightdeck

@Suite("ShellFeedTests")
struct ShellFeedTests {
    @Test("Parse extended zsh history line with timestamp and command")
    func parseExtendedZshHistoryLine() {
        let line = ": 1788952602:0;git commit -m 'initial commit'"
        let parsed = ShellFeed.parseHistoryLine(line)

        #expect(parsed != nil)
        #expect(parsed?.command == "git commit -m 'initial commit'")
        #expect(parsed?.timestamp.timeIntervalSince1970 == 1788952602)
    }

    @Test("Parse plain bash history line without metadata")
    func parsePlainHistoryLine() {
        let line = "swift test --filter ShellFeedTests"
        let parsed = ShellFeed.parseHistoryLine(line)

        #expect(parsed != nil)
        #expect(parsed?.command == "swift test --filter ShellFeedTests")
    }

    @Test("Parse empty or whitespace lines returns nil")
    func parseEmptyLine() {
        #expect(ShellFeed.parseHistoryLine("") == nil)
        #expect(ShellFeed.parseHistoryLine("   \n\t") == nil)
    }

    @Test("Command classification identifies git, build, and shell run types")
    func commandClassification() {
        #expect(ActivityEntry.Kind.forCommand("git status") == .git)
        #expect(ActivityEntry.Kind.forCommand("git diff HEAD") == .git)
        #expect(ActivityEntry.Kind.forCommand("swift build -c release") == .build)
        #expect(ActivityEntry.Kind.forCommand("cargo test") == .build)
        #expect(ActivityEntry.Kind.forCommand("npm run build") == .build)
        #expect(ActivityEntry.Kind.forCommand("ls -la /tmp") == .run)
        #expect(ActivityEntry.Kind.forCommand("cat README.md") == .run)
    }
}
