import Testing
@testable import Flightdeck

@Suite("Session pull request identity")
struct SessionPullRequestTests {
    private func session(url: String, number: Int? = nil) -> SessionAgg {
        var agg = SessionAgg(id: "s1", project: "p")
        agg.prUrl = url
        agg.prNumber = number
        return agg
    }

    @Test("A reported PR number is used as-is")
    func reportedNumberWins() {
        let agg = session(url: "https://github.com/runvendo/vendo/pull/1343", number: 1343)
        #expect(agg.resolvedPRNumber == 1343)
    }

    @Test("A missing PR number is recovered from the pull request URL")
    func numberRecoveredFromURL() {
        let agg = session(url: "https://github.com/runvendo/vendo/pull/829")
        #expect(agg.resolvedPRNumber == 829)
    }

    @Test("A trailing slash does not hide the number")
    func trailingSlashTolerated() {
        let agg = session(url: "https://github.com/runvendo/vendo/pull/911/")
        #expect(agg.resolvedPRNumber == 911)
    }

    @Test("A PR URL with extra path segments still resolves")
    func extraSegmentsTolerated() {
        let agg = session(url: "https://github.com/runvendo/vendo/pull/867/files")
        #expect(agg.resolvedPRNumber == 867)
    }

    @Test("An unparseable URL yields no number rather than a fabricated one")
    func noNumberInvented() {
        #expect(session(url: "https://github.com/runvendo/vendo").resolvedPRNumber == nil)
        #expect(session(url: "").resolvedPRNumber == nil)
        #expect(session(url: "not a url").resolvedPRNumber == nil)
    }

    @Test("A non-numeric segment after /pull/ is not mistaken for a number")
    func nonNumericSegmentRejected() {
        #expect(session(url: "https://github.com/runvendo/vendo/pull/new/branch").resolvedPRNumber == nil)
    }

    @Test("The title omits the number when none is known")
    func titleOmitsUnknownNumber() {
        #expect(session(url: "https://github.com/o/r/pull/5").prTitle == "GITHUB PULL REQUEST #5")
        #expect(session(url: "https://github.com/o/r").prTitle == "GITHUB PULL REQUEST")
    }

    @Test("Only web pull request links are offered for opening")
    func onlyWebLinksOpenable() {
        #expect(session(url: "https://github.com/o/r/pull/5").prLink?.absoluteString
                    == "https://github.com/o/r/pull/5")
        #expect(session(url: "http://github.example/o/r/pull/5").prLink != nil)
    }

    @Test("A non-web scheme in a transcript is never handed to the system")
    func nonWebSchemeRejected() {
        // Transcripts are shareable, so prUrl is attacker-influenced input.
        #expect(session(url: "file:///etc/passwd").prLink == nil)
        #expect(session(url: "javascript:alert(1)").prLink == nil)
        #expect(session(url: "ftp://example.com/x").prLink == nil)
        #expect(session(url: "HTTPS://github.com/o/r/pull/5").prLink != nil)
        #expect(session(url: "").prLink == nil)
        #expect(session(url: "   ").prLink == nil)
    }

    @Test("The subtitle prefers the repository and falls back to the URL")
    func subtitlePrefersRepository() {
        var agg = session(url: "https://github.com/runvendo/vendo/pull/1")
        #expect(agg.prSubtitle == "https://github.com/runvendo/vendo/pull/1")
        agg.prRepository = "runvendo/vendo"
        #expect(agg.prSubtitle == "runvendo/vendo")
    }
}
