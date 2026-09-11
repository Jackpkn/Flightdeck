import Testing
@testable import Flightdeck

@Suite("Presentation redactor")
struct RedactorTests {
    private func redactor(_ projects: [String]) -> Redactor {
        var r = Redactor(isEnabled: true)
        r.register(projects: projects)
        return r
    }

    @Test("Disabled, every value passes through untouched")
    func passthroughWhenOff() {
        var off = Redactor(isEnabled: false)
        off.register(projects: ["fleetsync", "integ"])
        #expect(off.project("fleetsync") == "fleetsync")
        #expect(off.title("Rolling reservation fleet", project: "fleetsync") == "Rolling reservation fleet")
        #expect(off.branch("feat/nfs-ts") == "feat/nfs-ts")
        #expect(off.path("/Users/someone/Work/fleetsync/App.swift") == "/Users/someone/Work/fleetsync/App.swift")
    }

    @Test("Project names become neutral labels")
    func projectsMasked() {
        let r = redactor(["fleetsync", "integ", "Flightdeck"])
        #expect(r.project("fleetsync") != "fleetsync")
        #expect(r.project("integ") != "integ")
        #expect(r.project("fleetsync").hasPrefix("project-"))
    }

    @Test("Labels are assigned in a stable order, not by insertion")
    func labelsStable() {
        let a = redactor(["fleetsync", "integ", "Flightdeck"])
        let b = redactor(["integ", "Flightdeck", "fleetsync"])
        #expect(a.project("fleetsync") == b.project("fleetsync"))
        #expect(a.project("integ") == b.project("integ"))
    }

    @Test("Distinct projects never collide on one label")
    func labelsUnique() {
        let r = redactor(["fleetsync", "integ", "Flightdeck", "vendo", "EgoInteract"])
        let labels = ["fleetsync", "integ", "Flightdeck", "vendo", "EgoInteract"].map(r.project)
        #expect(Set(labels).count == 5)
    }

    @Test("An unregistered project is still masked, never leaked")
    func unknownProjectMasked() {
        let r = redactor(["fleetsync"])
        let masked = r.project("some-client-repo")
        #expect(masked != "some-client-repo")
        #expect(!masked.isEmpty)
    }

    @Test("Session titles are prompt-derived, so they are replaced entirely")
    func titlesReplaced() {
        let r = redactor(["fleetsync"])
        let masked = r.title("Rolling reservation fleet coordination engine", project: "fleetsync")
        #expect(!masked.contains("reservation"))
        #expect(!masked.contains("fleet"))
        #expect(masked.contains(r.project("fleetsync")))
    }

    @Test("Branch names keep their shape but lose the subject")
    func branchesMasked() {
        let r = redactor(["integ"])
        #expect(r.branch("feat/nfs-ts") == "feat/branch")
        #expect(r.branch("bugfix/client-login") == "bugfix/branch")
        #expect(r.branch("HEAD") == "HEAD")
        #expect(r.branch("main") == "main")
        #expect(r.branch("") == "")
    }

    @Test("Paths lose the home directory and the project name")
    func pathsMasked() {
        let r = redactor(["fleetsync"])
        let masked = r.path("/Users/someone/Work/fleetsync/Sources/Booking.swift")
        #expect(!masked.contains("someone"))
        #expect(!masked.contains("fleetsync"))
        #expect(masked.hasSuffix(".swift"), "the extension carries real signal and is kept")
    }

    @Test("A file name keeps its extension and nothing else")
    func fileNamesMasked() {
        let r = redactor(["integ"])
        #expect(r.fileName("pr911-reply.md").hasSuffix(".md"))
        #expect(!r.fileName("pr911-reply.md").contains("pr911"))
        #expect(r.fileName("Makefile").hasPrefix("file-"))
    }

    @Test("Different files stay visibly different once masked")
    func fileNamesStayDistinct() {
        // Collapsing every .py to "file.py" made a churn list of three separate
        // files read as the same row repeated — a masked view has to stay useful.
        let r = redactor(["integ"])
        let masked = ["cli.py", "config.py", "pipeline.py"].map(r.fileName)
        #expect(Set(masked).count == 3)
        #expect(masked.allSatisfy { $0.hasSuffix(".py") })
        #expect(masked.allSatisfy { !$0.contains("cli") && !$0.contains("config") })
    }

    @Test("The same file masks to the same name every time")
    func fileNamesStable() {
        let a = redactor(["integ"])
        let b = redactor(["integ"])
        #expect(a.fileName("pipeline.py") == b.fileName("pipeline.py"))
    }

    @Test("The machine name is replaced")
    func hostnameMasked() {
        let r = redactor(["integ"])
        #expect(r.hostname("pawans-macbook-air-2") == "this-mac")
    }

    @Test("Session identifiers are shortened past recognition")
    func sessionIdsMasked() {
        let r = redactor(["integ"])
        let masked = r.sessionID("d7e54d41-e84d-440c-a63f-9cb032d7f5a7")
        #expect(!masked.contains("d7e54d41"))
        #expect(masked.count <= 10)
    }

    @Test("Masking a session changes no measured figure")
    func figuresUntouched() {
        var session = SessionAgg(id: "abc", project: "client-repo")
        session.branch = "feat/secret-launch"
        session.aiTitle = "Rewrite the billing reconciliation job"
        session.lastPrompt = "the client wants invoices grouped by region"
        session.lastFile = "/Users/someone/Work/client-repo/Billing.swift"
        session.inputTokens = 1_498
        session.outputTokens = 960_780
        session.cacheReadTokens = 172_256_441
        session.liveTotalCost = 72.9633
        session.contextTokens = 731_996
        session.noteFileModified(trackingPath: "/Users/someone/Work/client-repo/A.swift",
                                 realParentDir: nil)
        session.noteFileModified(trackingPath: "/Users/someone/Work/client-repo/B.swift",
                                 realParentDir: nil)

        var r = Redactor(isEnabled: true)
        r.register(projects: ["client-repo"])
        let masked = session.redacted(by: r)

        // The numbers are the product. Masking any of them would make a shared
        // screen a lie, which is the opposite of what this mode is for.
        #expect(masked.totalCost == session.totalCost)
        #expect(masked.totalTokens == session.totalTokens)
        #expect(masked.contextTokens == session.contextTokens)
        #expect(masked.inputTokens == session.inputTokens)
        #expect(masked.outputTokens == session.outputTokens)
        #expect(masked.filesModifiedCount == session.filesModifiedCount)
        #expect(masked.id == session.id, "the key views look sessions up by must survive")

        // And the identifying strings really are gone.
        #expect(!masked.project.contains("client"))
        #expect(!masked.branch.contains("secret"))
        #expect(!masked.aiTitle.contains("billing"))
        #expect(!masked.aiTitle.contains("reconciliation"))
        #expect(masked.lastPrompt.isEmpty)
        #expect(!masked.lastFile.contains("someone"))
        #expect(!masked.lastFile.contains("Billing"))
        // filesModified is intentionally left real: it feeds the git probe and a
        // displayed count. Its one display site masks the paths itself.
        #expect(masked.filesModified == session.filesModified)
    }

    @Test("Disabled, a session is returned completely unchanged")
    func sessionUntouchedWhenOff() {
        var session = SessionAgg(id: "abc", project: "client-repo")
        session.branch = "feat/secret-launch"
        session.lastFile = "/Users/someone/Work/client-repo/Billing.swift"
        let same = session.redacted(by: Redactor(isEnabled: false))
        #expect(same.project == session.project)
        #expect(same.branch == session.branch)
        #expect(same.lastFile == session.lastFile)
        #expect(same.aiTitle == session.aiTitle)
        #expect(same.lastPrompt == session.lastPrompt)
        #expect(same.filesModified == session.filesModified)
    }
}
