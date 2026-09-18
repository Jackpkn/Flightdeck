import Foundation
import Testing
@testable import Flightdeck

@Suite("Epistemic Causal Substrate (ECS)")
struct CausalMemoryTests {

    @Test("AuthorityLevel accurately assigns trust scores and quarantines L4")
    func authorityLevelQuarantineAndTrust() {
        #expect(AuthorityLevel.L0.trustScore == 1.0)
        #expect(!AuthorityLevel.L0.isQuarantined)

        #expect(AuthorityLevel.L1.trustScore == 0.95)
        #expect(!AuthorityLevel.L1.isQuarantined)

        #expect(AuthorityLevel.L3.trustScore == 0.85)
        #expect(!AuthorityLevel.L3.isQuarantined)

        #expect(AuthorityLevel.L2.trustScore == 0.70)
        #expect(!AuthorityLevel.L2.isQuarantined)

        #expect(AuthorityLevel.L4.trustScore == 0.30)
        #expect(AuthorityLevel.L4.isQuarantined)
    }

    @Test("MemoryCapsule microDirective generates ultra-dense actionable context")
    func microDirectiveFormatting() {
        let capsule = MemoryCapsule(
            project: "Flightdeck",
            filePath: "Sources/Flightdeck/DevCleaner.swift",
            symbol: "ContextWindowSource",
            kind: .trap,
            triggerPattern: ".measured",
            failureSignature: "error: type ContextWindowSource has no member 'measured'",
            resolution: "Valid cases are .statusline, .inferred, .fallback"
        )

        let directive = capsule.microDirective
        #expect(directive.contains("⚠️ TRAP: `Sources/Flightdeck/DevCleaner.swift` (symbol: ContextWindowSource)"))
        #expect(directive.contains("Trigger: .measured"))
        #expect(directive.contains("Failure: error: type ContextWindowSource has no member 'measured'"))
        #expect(directive.contains("Resolution: Valid cases are .statusline, .inferred, .fallback"))
    }

    @Test("CausalMemoryEngine normalizes file paths correctly")
    func pathNormalization() {
        #expect(CausalMemoryEngine.normalizePath("./Sources/Flightdeck/App.swift") == "Sources/Flightdeck/App.swift")
        #expect(CausalMemoryEngine.normalizePath("Sources/Flightdeck/App.swift") == "Sources/Flightdeck/App.swift")
        #expect(CausalMemoryEngine.normalizePath("/Users/test/repo/Sources/App.swift", relativeTo: "/Users/test/repo") == "Sources/App.swift")
    }

    @Test("ActivityDatabase saves and retrieves memory capsules with hit recording")
    func databaseCapsuleStorageAndHits() throws {
        let db = try ActivityDatabase.inMemory()

        let capsule = MemoryCapsule(
            project: "TestProj",
            filePath: "Sources/Test.swift",
            kind: .rule,
            triggerPattern: "SPM build flag",
            resolution: "Use -Xswiftc -suppress-warnings"
        )

        db.saveMemoryCapsule(capsule)

        let fetched = db.fetchMemoryCapsules(project: "TestProj", filePath: "Sources/Test.swift", status: .active)
        #expect(fetched.count == 1)
        #expect(fetched.first?.resolution == "Use -Xswiftc -suppress-warnings")
        #expect(fetched.first?.hitCount == 0)

        // Check hazards invokes recordMemoryHit
        let hazards = CausalMemoryEngine.checkHazards(for: ["Sources/Test.swift"], project: "TestProj", in: db)
        #expect(hazards.count == 1)

        let afterHit = db.fetchMemoryCapsules(project: "TestProj", filePath: "Sources/Test.swift", status: .active)
        #expect(afterHit.first?.hitCount == 1)
    }

    @Test("formatMicroCapsules builds clean Markdown block")
    func formatMicroCapsulesMarkdown() {
        let capsule = MemoryCapsule(
            project: "Flightdeck",
            filePath: "Sources/Flightdeck/DevCleaner.swift",
            kind: .rule,
            triggerPattern: "Cargo cache cleanup",
            resolution: "Registry cache lives in ~/.cargo/registry/cache"
        )

        let block = CausalMemoryEngine.formatMicroCapsules([capsule], project: "Flightdeck")
        #expect(block.contains("### FLIGHTDECK CAUSAL MEMORY [FLIGHTDECK]"))
        #expect(block.contains("✓ RULE: `Sources/Flightdeck/DevCleaner.swift`"))
        #expect(block.contains("Resolution: Registry cache lives in ~/.cargo/registry/cache"))
    }

    @Test("Causal edges and recursive blast radius CTE in Swift")
    func recursiveBlastRadiusOverCausalEdges() throws {
        let db = try ActivityDatabase.inMemory()

        let prob = MemoryCapsule(
            id: "prob-001",
            project: "Flightdeck",
            filePath: "Sources/Error.swift",
            kind: .trap,
            triggerPattern: "compile error",
            resolution: "needs fix"
        )
        let fix = MemoryCapsule(
            id: "fix-001",
            project: "Flightdeck",
            filePath: "Sources/Fix.swift",
            kind: .rule,
            triggerPattern: "compile error",
            resolution: "use correct member"
        )
        let dep = MemoryCapsule(
            id: "dep-001",
            project: "Flightdeck",
            filePath: "Sources/Dep.swift",
            kind: .invariant,
            triggerPattern: "dep constraint",
            resolution: "version 2"
        )

        db.saveMemoryCapsule(prob)
        db.saveMemoryCapsule(fix)
        db.saveMemoryCapsule(dep)

        // fix SOLVES prob, prob DEPENDS_ON dep
        CausalMemoryEngine.solveProblem(problemId: "prob-001", with: "fix-001", in: db)
        db.saveMemoryEdge(MemoryEdge(
            fromCapsuleId: "prob-001",
            toCapsuleId: "dep-001",
            edgeType: .dependsOn
        ))

        // Blast radius from fix-001 traverses SOLVES -> prob-001 -> dep-001
        let blastFromFix = CausalMemoryEngine.computeBlastRadius(for: "fix-001", maxDepth: 3, in: db)
        #expect(blastFromFix.contains("prob-001"))
        #expect(blastFromFix.contains("dep-001"))

        // Blast radius from prob-001 traverses incoming SOLVES -> fix-001 and outgoing DEPENDS_ON -> dep-001
        let blastFromProb = CausalMemoryEngine.computeBlastRadius(for: "prob-001", maxDepth: 3, in: db)
        #expect(blastFromProb.contains("fix-001"))
        #expect(blastFromProb.contains("dep-001"))
    }

    @Test("CUPMem write-side adjudication in Swift: L1 supersedes L2")
    func cupmemWriteSideAdjudicationInSwift() throws {
        let db = try ActivityDatabase.inMemory()

        var oldL2 = MemoryCapsule(
            id: "old-l2",
            project: "Flightdeck",
            filePath: "Sources/Path.swift",
            kind: .trap,
            authority: .L2,
            triggerPattern: "cache dir",
            resolution: "use ~/.cargo/cache"
        )
        _ = CausalMemoryEngine.adjudicate(newCapsule: &oldL2, in: db)

        var newL1 = MemoryCapsule(
            id: "new-l1",
            project: "Flightdeck",
            filePath: "Sources/Path.swift",
            kind: .rule,
            authority: .L1,
            triggerPattern: "cache dir",
            resolution: "use ~/.cargo/registry/cache"
        )
        let res = CausalMemoryEngine.adjudicate(newCapsule: &newL1, in: db)

        #expect(res.affected.count == 1)
        #expect(res.affected.first?.status == .superseded)
        #expect(res.affected.first?.invalidatedBy == "new-l1")

        let edges = db.fetchMemoryEdges(fromId: "new-l1", toId: "old-l2", type: .supersedes)
        #expect(edges.count == 1)
    }

    @Test("Cross-agent conflict in Swift produces CONFLICT directive")
    func crossAgentConflictInSwift() throws {
        let db = try ActivityDatabase.inMemory()

        var capA = MemoryCapsule(
            id: "cap-A",
            project: "Flightdeck",
            filePath: "Sources/Config.swift",
            subject: "DBLocation",
            kind: .rule,
            authority: .L2,
            triggerPattern: "config DB",
            resolution: "Path A"
        )
        _ = CausalMemoryEngine.adjudicate(newCapsule: &capA, in: db)

        var capB = MemoryCapsule(
            id: "cap-B",
            project: "Flightdeck",
            filePath: "Sources/Config.swift",
            subject: "DBLocation",
            kind: .rule,
            authority: .L2,
            triggerPattern: "config DB",
            resolution: "Path B"
        )
        let res = CausalMemoryEngine.adjudicate(newCapsule: &capB, in: db)

        #expect(res.persisted.conflictNote != nil)
        #expect(res.persisted.microDirective.contains("[CONFLICT: DBLocation]"))
        #expect(res.persisted.microDirective.contains("Two sources disagree"))

        let edges = db.fetchMemoryEdges(fromId: "cap-B", toId: "cap-A", type: .contradicts)
        #expect(edges.count == 1)
    }

    @Test("Bitemporal queries and as-of point-in-time validity semantics")
    func bitemporalValidityAndInvalidation() throws {
        let db = try ActivityDatabase.inMemory()
        let now = Date()
        let past = now.addingTimeInterval(-3600)
        let future = now.addingTimeInterval(3600)

        var capsule = MemoryCapsule(
            id: "bitemp-001",
            project: "Flightdeck",
            filePath: "Sources/Bitemporal.swift",
            kind: .rule,
            triggerPattern: "bitemporal pattern",
            resolution: "Valid initially",
            validFrom: past,
            validUntil: future
        )
        db.saveMemoryCapsule(capsule)

        let initial = db.fetchMemoryCapsule(id: "bitemp-001")
        #expect(initial != nil)
        #expect(initial?.validUntil != nil)
        #expect(initial?.invalidatedBy == nil)

        // Simulate supersession / invalidation
        capsule.validUntil = now
        capsule.invalidatedBy = "bitemp-002"
        capsule.status = .superseded
        db.saveMemoryCapsule(capsule)

        let after = db.fetchMemoryCapsule(id: "bitemp-001")
        #expect(after?.status == .superseded)
        #expect(after?.invalidatedBy == "bitemp-002")
    }

    @Test("7-day retention floor blocks dream compaction of recently superseded capsules")
    func sevenDayRetentionFloorProtectsRecentData() throws {
        let db = try ActivityDatabase.inMemory()
        let now = Date()
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!

        let oldDeadCapsule = MemoryCapsule(
            id: "old-dead",
            project: "Flightdeck",
            filePath: "Sources/Old.swift",
            kind: .rule,
            triggerPattern: "old pattern",
            resolution: "old resolution",
            status: .superseded,
            updatedAt: tenDaysAgo
        )
        let recentDeadCapsule = MemoryCapsule(
            id: "recent-dead",
            project: "Flightdeck",
            filePath: "Sources/Recent.swift",
            kind: .rule,
            triggerPattern: "recent pattern",
            resolution: "recent resolution",
            status: .superseded,
            updatedAt: twoDaysAgo
        )

        db.saveMemoryCapsule(oldDeadCapsule)
        db.saveMemoryCapsule(recentDeadCapsule)

        // Compaction with 7-day retention floor
        let res = db.compactTombstones(retentionDays: 7)
        #expect(res.purgedTombstones == 1)

        // Old capsule (>7 days) was purged
        #expect(db.fetchMemoryCapsule(id: "old-dead") == nil)
        // Recent capsule (2 days ago) was protected by retention floor!
        #expect(db.fetchMemoryCapsule(id: "recent-dead") != nil)
    }

    @Test("CUPMem topological propagation cascades invalidation to dependent nodes")
    func topologicalPropagationCascadesInvalidation() throws {
        let db = try ActivityDatabase.inMemory()

        var premise = MemoryCapsule(
            id: "premise-001",
            project: "Flightdeck",
            filePath: "Sources/Premise.swift",
            symbol: "BaseConfig",
            kind: .rule,
            authority: .L2,
            triggerPattern: "BaseConfig location",
            resolution: "Use ~/.flightdeck"
        )
        _ = CausalMemoryEngine.adjudicate(newCapsule: &premise, in: db)

        let deduction = MemoryCapsule(
            id: "deduction-001",
            project: "Flightdeck",
            filePath: "Sources/Deduction.swift",
            symbol: "DerivedService",
            kind: .rule,
            authority: .L2,
            triggerPattern: "DerivedService setup",
            resolution: "Connect to BaseConfig at ~/.flightdeck"
        )
        db.saveMemoryCapsule(deduction)

        // deduction DEPENDS_ON premise
        db.saveMemoryEdge(MemoryEdge(
            fromCapsuleId: deduction.id,
            toCapsuleId: premise.id,
            edgeType: .dependsOn
        ))

        // Now higher authority L1 compiler/verified evidence supersedes premise!
        var verifiedPremise = MemoryCapsule(
            id: "premise-002",
            project: "Flightdeck",
            filePath: "Sources/Premise.swift",
            symbol: "BaseConfig",
            kind: .rule,
            authority: .L1, // Higher authority!
            triggerPattern: "BaseConfig location",
            resolution: "Use ~/Library/Application Support/Flightdeck"
        )
        let adj = CausalMemoryEngine.adjudicate(newCapsule: &verifiedPremise, in: db)

        // Both old premise and downstream deduction are in affected!
        #expect(adj.affected.contains(where: { $0.id == "premise-001" }))
        #expect(adj.affected.contains(where: { $0.id == "deduction-001" }))

        // Downstream deduction was topologically flagged as stale with dependency note!
        let reloadedDeduction = db.fetchMemoryCapsule(id: "deduction-001")
        #expect(reloadedDeduction?.anchorStatus == .stale)
        #expect(reloadedDeduction?.conflictNote?.contains("Dependency premise") == true)
    }

    @Test("90-day aging policy archives unresolved equal-authority conflicts")
    func unresolvedConflictAgingPolicyAfter90Days() throws {
        let db = try ActivityDatabase.inMemory()

        let ninetyFiveDaysAgo = Calendar.current.date(byAdding: .day, value: -95, to: Date())!
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!

        let oldConflict = MemoryCapsule(
            id: "conflict-old",
            project: "Flightdeck",
            filePath: "Sources/Engine.swift",
            symbol: "runEngine",
            kind: .rule,
            authority: .L2,
            triggerPattern: "runEngine config",
            resolution: "old conflicting claim",
            status: .conflicted,
            conflictNote: "Unresolved L2 disagreement",
            updatedAt: ninetyFiveDaysAgo
        )

        let recentConflict = MemoryCapsule(
            id: "conflict-recent",
            project: "Flightdeck",
            filePath: "Sources/Engine.swift",
            symbol: "runEngine",
            kind: .rule,
            authority: .L2,
            triggerPattern: "runEngine config",
            resolution: "recent conflicting claim",
            status: .conflicted,
            conflictNote: "Recent L2 disagreement",
            updatedAt: tenDaysAgo
        )

        db.saveMemoryCapsule(oldConflict)
        db.saveMemoryCapsule(recentConflict)

        // Run compaction with 90-day conflict aging policy
        let res = db.compactTombstones(retentionDays: 7, maxConflictAgeDays: 90)
        #expect(res.archivedConflicts == 1)

        // The 95-day-old conflict is aged out and archived to obsolete
        let archived = db.fetchMemoryCapsule(id: "conflict-old")
        #expect(archived?.status == .obsolete)
        #expect(archived?.conflictNote?.contains("[Archived: unresolved after 90 days]") == true)

        // The 10-day-old conflict remains active in conflicted state
        let activeConflict = db.fetchMemoryCapsule(id: "conflict-recent")
        #expect(activeConflict?.status == .conflicted)
    }

    @Test("Re-verification path for stale dependents requires explicit re-affirmation")
    func reverificationPathForStaleDependents() throws {
        let db = try ActivityDatabase.inMemory()

        // 1. Initial premise and dependent deduction
        var premise = MemoryCapsule(
            id: "premise-v1",
            project: "Flightdeck",
            filePath: "Sources/Storage.swift",
            symbol: "StorageEngine",
            kind: .rule,
            authority: .L2,
            triggerPattern: "Storage directory",
            resolution: "Use ~/.flightdeck"
        )
        _ = CausalMemoryEngine.adjudicate(newCapsule: &premise, in: db)

        let deduction = MemoryCapsule(
            id: "deduction-v1",
            project: "Flightdeck",
            filePath: "Sources/Worker.swift",
            symbol: "WorkerPool",
            kind: .rule,
            authority: .L2,
            triggerPattern: "Worker cache location",
            resolution: "Store in ~/.flightdeck/workers"
        )
        db.saveMemoryCapsule(deduction)
        db.saveMemoryEdge(MemoryEdge(
            fromCapsuleId: deduction.id,
            toCapsuleId: premise.id,
            edgeType: .dependsOn
        ))

        // 2. Premise superseded by higher authority L1
        var premiseV2 = MemoryCapsule(
            id: "premise-v2",
            project: "Flightdeck",
            filePath: "Sources/Storage.swift",
            symbol: "StorageEngine",
            kind: .rule,
            authority: .L1,
            triggerPattern: "Storage directory",
            resolution: "Use ~/Library/Application Support/Flightdeck"
        )
        _ = CausalMemoryEngine.adjudicate(newCapsule: &premiseV2, in: db)

        // Deduction is now stale due to cascade
        let staleDeduction = db.fetchMemoryCapsule(id: "deduction-v1")
        #expect(staleDeduction?.anchorStatus == .stale)

        // 3. Re-verification path: In ECS, stale dependents are NOT automatically un-staled.
        // The developer/agent must re-affirm the deduction against the new premise.
        var reaffirmedDeduction = MemoryCapsule(
            id: "deduction-v2",
            project: "Flightdeck",
            filePath: "Sources/Worker.swift",
            symbol: "WorkerPool",
            kind: .rule,
            authority: .L1, // Re-verified with verified compiler authority
            triggerPattern: "Worker cache location",
            resolution: "Store in ~/Library/Application Support/Flightdeck/workers"
        )
        _ = CausalMemoryEngine.adjudicate(newCapsule: &reaffirmedDeduction, in: db)
        db.saveMemoryEdge(MemoryEdge(
            fromCapsuleId: reaffirmedDeduction.id,
            toCapsuleId: premiseV2.id,
            edgeType: .dependsOn
        ))

        // Now deduction-v2 is active and verified, linked to premise-v2
        let activeDeduction = db.fetchMemoryCapsule(id: "deduction-v2")
        #expect(activeDeduction?.status == .active)
        #expect(activeDeduction?.authority == .L1)

        // And forward traversal along DEPENDS_ON from deduction-v2 reaches its dependency premise-v2
        let reachable = db.computeBlastRadius(capsuleId: "deduction-v2", maxDepth: 3)
        #expect(reachable.contains("premise-v2"))
    }

    @Test("reverifyStaleDependents recovers valid deductions and rewires edges")
    func reverifyStaleDependentsRecoversValidDeductions() throws {
        let db = try ActivityDatabase.inMemory()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let workerFile = tmpDir.appendingPathComponent("Worker.swift")
        try "class WorkerPool { func run() { print(\"ok\") } }".write(to: workerFile, atomically: true, encoding: .utf8)

        let premiseOld = MemoryCapsule(
            id: "premise-old",
            project: "Flightdeck",
            filePath: "Storage.swift",
            symbol: "StorageEngine",
            kind: .rule,
            authority: .L2,
            triggerPattern: "storage",
            resolution: "old storage",
            status: .superseded,
            invalidatedBy: "premise-new"
        )
        let premiseNew = MemoryCapsule(
            id: "premise-new",
            project: "Flightdeck",
            filePath: "Storage.swift",
            symbol: "StorageEngine",
            kind: .rule,
            authority: .L1,
            triggerPattern: "storage",
            resolution: "new storage",
            status: .active
        )
        let deduction = MemoryCapsule(
            id: "deduction-001",
            project: "Flightdeck",
            filePath: "Worker.swift",
            symbol: "WorkerPool",
            kind: .rule,
            authority: .L2,
            triggerPattern: "WorkerPool",
            resolution: "use storage",
            status: .stale,
            anchorStatus: .stale,
            conflictNote: "Dependency was superseded"
        )

        db.saveMemoryCapsule(premiseOld)
        db.saveMemoryCapsule(premiseNew)
        db.saveMemoryCapsule(deduction)
        db.saveMemoryEdge(MemoryEdge(fromCapsuleId: deduction.id, toCapsuleId: premiseOld.id, edgeType: .dependsOn))

        let res = CausalMemoryEngine.reverifyStaleDependents(project: "Flightdeck", cwd: tmpDir.path, in: db)
        #expect(res.recovered == 1)
        #expect(res.remainedStale == 0)

        let reloaded = db.fetchMemoryCapsule(id: "deduction-001")
        #expect(reloaded?.status == .active)
        #expect(reloaded?.anchorStatus == .verified)
        #expect(reloaded?.conflictNote?.contains("Re-verified") == true)

        // Verify DEPENDS_ON edge was rewired to premise-new
        let newEdges = db.fetchMemoryEdges(fromId: "deduction-001", type: .dependsOn)
        #expect(newEdges.contains(where: { $0.toCapsuleId == "premise-new" }))
    }

    @Test("computeBlastRadiusDetails handles limit truncation and deterministic depth-boundary ties")
    func blastRadiusTruncationAndDeterministicTieBreaking() throws {
        let db = try ActivityDatabase.inMemory()

        let seed = MemoryCapsule(
            id: "seed-hub",
            project: "Flightdeck",
            filePath: "Core.swift",
            symbol: "CoreHub",
            kind: .rule,
            authority: .L1,
            triggerPattern: "core",
            resolution: "core fix"
        )
        db.saveMemoryCapsule(seed)

        // Create 8 targets at depth 1 with unsorted IDs: z-001, m-002, a-003, etc.
        let targetIds = ["z-001", "m-002", "a-003", "k-004", "b-005", "y-006", "c-007", "d-008"]
        for tid in targetIds {
            let cap = MemoryCapsule(
                id: tid,
                project: "Flightdeck",
                filePath: "Target.swift",
                symbol: tid,
                kind: .rule,
                authority: .L2,
                triggerPattern: tid,
                resolution: tid
            )
            db.saveMemoryCapsule(cap)
            db.saveMemoryEdge(MemoryEdge(fromCapsuleId: "seed-hub", toCapsuleId: tid, edgeType: .causes))
        }

        // Request with limit: 4
        let result = db.computeBlastRadiusDetails(capsuleId: "seed-hub", maxDepth: 2, limit: 4)
        #expect(result.truncated == true)
        #expect(result.totalEstimate == 8)
        #expect(result.nodes.count == 4)

        // Tie-breaking check: at equal depth 1, nodes must be sorted deterministically by id ASC: a-003, b-005, c-007, d-008
        #expect(result.nodes == ["a-003", "b-005", "c-007", "d-008"])
    }

    @Test("Adversarial content-dependency rewiring caveat: missing symbol leaves dependent stale")
    func adversarialContentDependencyLeavesDependentStale() throws {
        let db = try ActivityDatabase.inMemory()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Repo has StorageY.swift, but does NOT contain the legacy symbol "LegacyUserTable" that D asserts
        let fileY = tmpDir.appendingPathComponent("StorageY.swift")
        try "class ModernStorageService { func query() {} }".write(to: fileY, atomically: true, encoding: .utf8)

        let premiseOld = MemoryCapsule(
            id: "premise-path-x",
            project: "Flightdeck",
            filePath: "StorageX.swift",
            symbol: "StorageEngine",
            kind: .rule,
            authority: .L2,
            triggerPattern: "storage x",
            resolution: "old path",
            status: .superseded,
            invalidatedBy: "premise-path-y"
        )
        let premiseNew = MemoryCapsule(
            id: "premise-path-y",
            project: "Flightdeck",
            filePath: "StorageY.swift",
            symbol: "ModernStorageService",
            kind: .rule,
            authority: .L1,
            triggerPattern: "storage y",
            resolution: "new path",
            status: .active
        )
        // Dependent D made a claim about LegacyUserTable in StorageX
        let deduction = MemoryCapsule(
            id: "deduction-legacy-table",
            project: "Flightdeck",
            filePath: "StorageY.swift",
            symbol: "LegacyUserTable",
            kind: .rule,
            authority: .L2,
            triggerPattern: "legacy table query",
            resolution: "read from legacy table",
            status: .stale,
            anchorStatus: .stale,
            conflictNote: "Dependency was superseded"
        )

        db.saveMemoryCapsule(premiseOld)
        db.saveMemoryCapsule(premiseNew)
        db.saveMemoryCapsule(deduction)
        db.saveMemoryEdge(MemoryEdge(fromCapsuleId: deduction.id, toCapsuleId: premiseOld.id, edgeType: .dependsOn))

        // Re-verification loop runs: D fails symbol verification because LegacyUserTable does not exist in StorageY
        let res = CausalMemoryEngine.reverifyStaleDependents(project: "Flightdeck", cwd: tmpDir.path, in: db)
        #expect(res.recovered == 0)
        #expect(res.remainedStale == 1)

        let reloaded = db.fetchMemoryCapsule(id: "deduction-legacy-table")
        #expect(reloaded?.status == .stale)
        #expect(reloaded?.anchorStatus != .verified)
    }
}

