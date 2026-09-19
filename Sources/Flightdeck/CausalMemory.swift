import Foundation
import CryptoKit
import GRDB

// MARK: - Epistemic Causal Memory Models

/// The epistemic category of a causal memory capsule.
public enum MemoryKind: String, Codable, Sendable, CaseIterable {
    /// A mistake, compiler error, or test failure that an agent should avoid.
    case trap = "trap"
    /// A verified command, flag, or implementation pattern that succeeded.
    case rule = "rule"
    /// An architectural constraint or project-wide invariant.
    case invariant = "invariant"
    /// A falsified hypothesis (e.g., incorrect path or invalid assumption).
    case deadEnd = "dead_end"

    public var label: String {
        switch self {
        case .trap: return "HAZARD TRAP"
        case .rule: return "PROVEN RULE"
        case .invariant: return "INVARIANT"
        case .deadEnd: return "FALSIFIED HYPOTHESIS"
        }
    }

    public var badge: String {
        switch self {
        case .trap: return "⚠️ TRAP"
        case .rule: return "✓ RULE"
        case .invariant: return "⚓︎ INVARIANT"
        case .deadEnd: return "✕ DEAD END"
        }
    }
}

/// Authority level governing write-side trust (MemGuard & A-MemGuard architecture).
public enum AuthorityLevel: String, Codable, Sendable, CaseIterable {
    case L0 = "L0"   // Filesystem/git state (Ground truth, read-only)
    case L1 = "L1"   // Direct machine ground truth: AST symbols, compiler exit code, test pass (High, read-only)
    case L2 = "L2"   // Generic/legacy agent observation
    case L2a = "L2a" // Host agent LLM judgment (Contextual, high-reasoning, non-deterministic)
    case L2b = "L2b" // Transcript miner sequential inference (Deterministic pattern match, reproducible)
    case L3 = "L3"   // User explicit directive (High user intent, writable)
    case L4 = "L4"   // External document/web (Low, quarantined)

    public var isQuarantined: Bool {
        self == .L4
    }

    public var trustScore: Double {
        switch self {
        case .L0: return 1.0
        case .L1: return 0.95
        case .L3: return 0.85
        case .L2a: return 0.75
        case .L2b: return 0.70
        case .L2: return 0.70
        case .L4: return 0.30
        }
    }
}

/// The verification lifecycle of a memory capsule relative to Git tree state.
public enum MemoryStatus: String, Codable, Sendable, CaseIterable {
    /// Initial candidate hypothesis proposed by transcript miner.
    case candidate = "candidate"
    /// Actively verified against current repository state.
    case active = "active"
    /// File has been modified in Git; capsule requires verification.
    case unverified = "unverified"
    /// Inactive or expired assumption.
    case stale = "stale"
    /// Superseded by a newer verified memory.
    case superseded = "superseded"
    /// Low-trust external document pending verification.
    case quarantined = "quarantined"
    /// Candidate requires Gate 4 host-agent adjudication before active injection.
    case pendingAdjudication = "pending_adjudication"
    /// Contradictory claims at equal authority pending resolution.
    case conflicted = "conflicted"
    /// File was deleted or rule was explicitly refuted.
    case obsolete = "obsolete"
}

/// The causal relationship type between two memory capsules.
public enum CausalEdgeType: String, Codable, Sendable, CaseIterable {
    case causes = "CAUSES"              // A caused B
    case solves = "SOLVES"              // Fix solves problem / compiler error
    case dependsOn = "DEPENDS_ON"      // Component depends on dependency
    case contradicts = "CONTRADICTS"    // Mutually exclusive claims
    case supersedes = "SUPERSEDES"      // New capsule supersedes old
    case evidenceFor = "EVIDENCE_FOR"  // Provenance link
    case leadsToDeadEnd = "LEADS_TO_DEAD_END" // Failed solution attempt that led to error
}

/// A typed, bitemporal causal edge between memory capsules.
public struct MemoryEdge: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "memory_edges"

    public var id: String
    public var fromCapsuleId: String
    public var toCapsuleId: String
    public var edgeType: CausalEdgeType
    public var validFrom: Date
    public var validUntil: Date?
    public var recordedAt: Date
    public var invalidatedBy: String?

    public init(
        id: String = UUID().uuidString,
        fromCapsuleId: String,
        toCapsuleId: String,
        edgeType: CausalEdgeType,
        validFrom: Date = Date(),
        validUntil: Date? = nil,
        recordedAt: Date = Date(),
        invalidatedBy: String? = nil
    ) {
        self.id = id
        self.fromCapsuleId = fromCapsuleId
        self.toCapsuleId = toCapsuleId
        self.edgeType = edgeType
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.recordedAt = recordedAt
        self.invalidatedBy = invalidatedBy
    }
}

/// Hash-anchored verification status relative to git committed blobs.
public enum AnchorStatus: String, Codable, Sendable, CaseIterable {
    case verified = "verified"             // Content hash matches committed blob exactly
    case stale = "stale"                   // Hash changed, but referenced symbol persists
    case contradicted = "contradicted"     // Code changed and referenced symbol is gone
    case missingSource = "missing_source" // File deleted from repository
    case unverified = "unverified"         // Not yet verified against git repository
}

/// Git-anchored code verification contract (Context Fabric & Legendary-MCP pattern).
public struct MemoryAnchor: Codable, Sendable {
    public var filePath: String
    public var symbolName: String?
    public var contentHash: String
    public var commitSha: String

    public init(
        filePath: String,
        symbolName: String? = nil,
        contentHash: String = "",
        commitSha: String = "HEAD"
    ) {
        self.filePath = filePath
        self.symbolName = symbolName
        self.contentHash = contentHash
        self.commitSha = commitSha
    }
}

/// A deterministic, file-anchored causal memory capsule.
public struct MemoryCapsule: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "memory_capsules"

    public var id: String
    public var project: String
    public var filePath: String
    public var symbol: String?
    public var subject: String?
    public var predicate: String?
    public var objectValue: String?
    public var kind: MemoryKind
    public var authority: AuthorityLevel
    public var triggerPattern: String
    public var failureSignature: String?
    public var resolution: String
    public var originSessionId: String?
    public var source: String
    public var verifiedBy: String
    public var occurrenceCount: Int
    public var gitSha: String
    public var fileHash: String?
    public var confidence: Double
    public var hitCount: Int
    public var status: MemoryStatus
    public var anchorStatus: AnchorStatus
    public var conflictNote: String?
    public var validFrom: Date
    public var validUntil: Date?
    public var trialUntil: Date?
    public var recordedAt: Date
    public var invalidatedBy: String?
    public var createdAt: Date
    public var updatedAt: Date

    public var isProvisional: Bool {
        guard let trialUntil else { return false }
        return trialUntil > Date()
    }

    public init(
        id: String = UUID().uuidString,
        project: String,
        filePath: String,
        symbol: String? = nil,
        subject: String? = nil,
        predicate: String? = nil,
        objectValue: String? = nil,
        kind: MemoryKind,
        authority: AuthorityLevel = .L2,
        triggerPattern: String,
        failureSignature: String? = nil,
        resolution: String,
        originSessionId: String? = nil,
        source: String = "agent",
        verifiedBy: String = "compiler",
        occurrenceCount: Int = 1,
        gitSha: String = "HEAD",
        fileHash: String? = nil,
        confidence: Double = 1.0,
        hitCount: Int = 0,
        status: MemoryStatus = .active,
        anchorStatus: AnchorStatus = .unverified,
        conflictNote: String? = nil,
        validFrom: Date = Date(),
        validUntil: Date? = nil,
        trialUntil: Date? = nil,
        recordedAt: Date = Date(),
        invalidatedBy: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.project = project
        self.filePath = filePath
        self.symbol = symbol
        self.subject = subject
        self.predicate = predicate
        self.objectValue = objectValue
        self.kind = kind
        self.authority = authority
        self.triggerPattern = triggerPattern
        self.failureSignature = failureSignature
        self.resolution = resolution
        self.originSessionId = originSessionId
        self.source = source
        self.verifiedBy = verifiedBy
        self.occurrenceCount = occurrenceCount
        self.gitSha = gitSha
        self.fileHash = fileHash
        self.confidence = confidence
        self.hitCount = hitCount
        self.status = status
        self.anchorStatus = anchorStatus
        self.conflictNote = conflictNote
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.trialUntil = trialUntil
        self.recordedAt = recordedAt
        self.invalidatedBy = invalidatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Formats this capsule into a dense micro-directive (<60 tokens)
    /// with imperative staleness and conflict warnings.
    public var microDirective: String {
        if status == .quarantined {
            return "[QUARANTINED: `\(filePath)`]\n  ⚠️ External document pending verification against compiler/git evidence."
        }
        if status == .pendingAdjudication {
            return "[PENDING ADJUDICATION: `\(filePath)`]\n  ⚠️ Mined or multi-file candidate pending host-agent review."
        }
        if let conflictNote, !conflictNote.isEmpty {
            return "[CONFLICT: \(subject ?? symbol ?? filePath)]\n⚠️ Two sources disagree on this code region:\n\(conflictNote)\n  Review code before proceeding."
        }
        if kind == .deadEnd {
            var out = "[✕ DEAD END: `\(filePath)`] (Falsified Hypothesis - Do NOT attempt)"
            if let symbol, !symbol.isEmpty {
                out += " (symbol: `\(symbol)`)"
            }
            if !triggerPattern.isEmpty {
                out += "\n  Context: \(triggerPattern)"
            }
            out += "\n  Attempted Fix: \(resolution)"
            if let failureSignature, !failureSignature.isEmpty {
                out += "\n  Failure Result: \(failureSignature)"
            }
            return out
        }
        if anchorStatus == .stale || status == .stale {
            return "[STALE: `\(filePath)`]\n  ⚠️ Code changed since this was written; verify before trusting.\n  Trigger: \(triggerPattern)\n  Prior Fix: \(resolution)"
        }
        let verifiedTag = (anchorStatus == .verified) ? " (verified against committed code)" : ""
        var out = "\(kind.badge): `\(filePath)`\(verifiedTag)"
        if let symbol, !symbol.isEmpty {
            out += " (symbol: `\(symbol)`)"
        }
        out += "\n  Trigger: \(triggerPattern)"
        if let failureSignature, !failureSignature.isEmpty {
            out += "\n  Failure: \(failureSignature)"
        }
        out += "\n  Fix: \(resolution)"
        if isProvisional, let trialUntil {
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withFullDate]
            out += "\n  ⚠️ [PROVISIONAL TRIAL]: Adjudicated by host agent until \(df.string(from: trialUntil)); subject to demotion if refutation occurs."
        }
        return out
    }
}

// MARK: - Causal Memory Engine

/// Native Swift engine coordinating causal storage, recursive CTE graph traversal,
/// git blob verification, and write-side adjudication under <15MB RAM.
public struct CausalMemoryEngine: Sendable {

    /// Normalizes a file path relative to repository root or directory name.
    public static func normalizePath(_ rawPath: String, relativeTo cwd: String? = nil) -> String {
        var clean = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("./") {
            clean = String(clean.dropFirst(2))
        }
        guard let cwd, !cwd.isEmpty, clean.hasPrefix(cwd) else {
            return clean
        }
        let relative = clean.dropFirst(cwd.count)
        if relative.hasPrefix("/") {
            return String(relative.dropFirst())
        }
        return String(relative)
    }

    /// Computes SHA256 hash of data.
    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes SHA256 hash of a file on disk if it exists.
    public static func computeFileHash(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return sha256Hex(data)
    }

    /// Reads committed blob directly from git object store (not dirty working tree).
    public static func committedBlob(for filePath: String, commit: String = "HEAD", cwd: String?) -> Data? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let clean = normalizePath(filePath)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", cwd, "show", "\(commit):\(clean)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            return pipe.fileHandleForReading.readDataToEndOfFile()
        } catch {
            return nil
        }
    }

    /// Resolves current git commit SHA for a working directory.
    public static func currentGitSha(cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "UNKNOWN_GIT" }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", cwd, "rev-parse", "HEAD"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return "DETACHED" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return str.isEmpty ? "DETACHED" : str
        } catch {
            return "UNKNOWN_GIT"
        }
    }

    /// Verifies anchor against committed git blob (Context Fabric / Memory-MCP pattern).
    public static func verifyAnchor(_ anchor: MemoryAnchor, cwd: String?) -> AnchorStatus {
        guard let cwd, !cwd.isEmpty else { return .unverified }

        // 1. Read committed blob from git object store
        var blobData = committedBlob(for: anchor.filePath, commit: anchor.commitSha, cwd: cwd)
        if blobData == nil {
            // Fallback to local filesystem check
            let fullPath = (cwd as NSString).appendingPathComponent(anchor.filePath)
            guard FileManager.default.fileExists(atPath: fullPath),
                  let localData = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else {
                return .missingSource
            }
            blobData = localData
        }

        guard let blob = blobData else { return .missingSource }
        let currentHash = sha256Hex(blob)

        // 2. Exact hash match
        if !anchor.contentHash.isEmpty && currentHash == anchor.contentHash {
            return .verified
        }

        // 3. Hash changed — check if symbol persists in committed content
        guard let text = String(data: blob, encoding: .utf8) else {
            return .stale
        }

        if let symbol = anchor.symbolName, !symbol.isEmpty {
            if !text.contains(symbol) {
                return .contradicted // Symbol no longer exists
            }
        }

        return .stale // Region changed, but symbol persists
    }

    /// Links a solution capsule to a problem capsule with an explicit SOLVES edge.
    static func solveProblem(
        problemId: String,
        with solutionId: String,
        in database: ActivityDatabase?
    ) {
        guard let db = database else { return }
        let edge = MemoryEdge(
            fromCapsuleId: solutionId,
            toCapsuleId: problemId,
            edgeType: .solves
        )
        db.saveMemoryEdge(edge)
    }

    typealias BlastRadiusResult = ActivityDatabase.BlastRadiusResult

    /// Computes the blast radius of causal impacts using SQLite recursive CTE with limit cap.
    static func computeBlastRadius(
        for capsuleId: String,
        maxDepth: Int = 3,
        limit: Int = 100,
        in database: ActivityDatabase?
    ) -> [String] {
        guard let db = database else { return [] }
        return db.computeBlastRadius(capsuleId: capsuleId, maxDepth: maxDepth, limit: limit)
    }

    /// Computes the blast radius with deterministic tie-breaking and truncation metrics.
    static func computeBlastRadiusDetails(
        for capsuleId: String,
        maxDepth: Int = 3,
        limit: Int = 100,
        in database: ActivityDatabase?
    ) -> BlastRadiusResult {
        guard let db = database else { return BlastRadiusResult(nodes: [], truncated: false, totalEstimate: 0) }
        return db.computeBlastRadiusDetails(capsuleId: capsuleId, maxDepth: maxDepth, limit: limit)
    }

    /// Write-side adjudication: enforces CUPMem authority hierarchy, quarantines L4,
    /// and supersedes older assumptions via explicit SUPERSEDES edges.
    static func adjudicate(
        newCapsule: inout MemoryCapsule,
        in database: ActivityDatabase?
    ) -> (persisted: MemoryCapsule, affected: [MemoryCapsule]) {
        guard let db = database else { return (newCapsule, []) }

        // L4 external content is always quarantined
        if newCapsule.authority == .L4 {
            newCapsule.status = .quarantined
            newCapsule.confidence = 0.3
            db.saveMemoryCapsule(newCapsule)
            return (newCapsule, [])
        }

        db.saveMemoryCapsule(newCapsule)

        let existing = db.fetchMemoryCapsules(project: newCapsule.project, filePath: newCapsule.filePath, status: .active)
        var affected: [MemoryCapsule] = []

        for var old in existing {
            if old.id == newCapsule.id { continue }

            let sameSymbol = (old.symbol != nil && newCapsule.symbol != nil && old.symbol == newCapsule.symbol)
            let sameSubject = (old.subject != nil && newCapsule.subject != nil && old.subject == newCapsule.subject)

            if sameSymbol || sameSubject || old.filePath == newCapsule.filePath {
                // Authority comparison:
                if newCapsule.authority.trustScore > old.authority.trustScore {
                    // Supersede old assumption
                    old.status = .superseded
                    old.validUntil = Date()
                    old.invalidatedBy = newCapsule.id
                    old.updatedAt = Date()
                    db.saveMemoryCapsule(old)
                    affected.append(old)

                    let edge = MemoryEdge(
                        fromCapsuleId: newCapsule.id,
                        toCapsuleId: old.id,
                        edgeType: .supersedes
                    )
                    db.saveMemoryEdge(edge)

                    // CUPMem Topology-triggered propagation (Type II conflict resolution):
                    // When an atom is superseded, cascade downstream to any active capsule that DEPENDS_ON it.
                    let depEdges = db.fetchMemoryEdges(toId: old.id, type: .dependsOn)
                    for depEdge in depEdges {
                        if var depCapsule = db.fetchMemoryCapsule(id: depEdge.fromCapsuleId), depCapsule.status == .active {
                            depCapsule.anchorStatus = .stale
                            depCapsule.conflictNote = "⚠️ Dependency premise `\(old.filePath)` was superseded by `\(newCapsule.id)`."
                            depCapsule.updatedAt = Date()
                            db.saveMemoryCapsule(depCapsule)
                            affected.append(depCapsule)
                        }
                    }
                } else if newCapsule.authority.trustScore == old.authority.trustScore {
                    // Equal authority contradiction -> mark CONFLICTED
                    if newCapsule.resolution != old.resolution {
                        let note = "• Prior: \(old.resolution)\n  • New: \(newCapsule.resolution)"
                        old.status = .conflicted
                        newCapsule.status = .conflicted
                        old.conflictNote = note
                        newCapsule.conflictNote = note
                        old.updatedAt = Date()
                        newCapsule.updatedAt = Date()
                        db.saveMemoryCapsule(old)
                        db.saveMemoryCapsule(newCapsule)
                        affected.append(old)

                        let edge = MemoryEdge(
                            fromCapsuleId: newCapsule.id,
                            toCapsuleId: old.id,
                            edgeType: .contradicts
                        )
                        db.saveMemoryEdge(edge)
                    }
                }
            }
        }

        return (newCapsule, affected)
    }

    /// Checks active hazard traps for a set of file paths on-demand.
    static func checkHazards(
        for filePaths: [String],
        project: String,
        cwd: String? = nil,
        in database: ActivityDatabase?
    ) -> [MemoryCapsule] {
        guard let db = database else { return [] }
        var results: [MemoryCapsule] = []

        for path in filePaths {
            let normalized = normalizePath(path, relativeTo: cwd)
            let capsules = db.fetchMemoryCapsules(project: project, filePath: normalized, status: .active)
            for var c in capsules {
                // On-demand anchor verification
                let anchor = MemoryAnchor(
                    filePath: c.filePath,
                    symbolName: c.symbol,
                    contentHash: c.fileHash ?? "",
                    commitSha: c.gitSha
                )
                let status = verifyAnchor(anchor, cwd: cwd)
                c.anchorStatus = status

                if status == .contradicted || status == .missingSource {
                    // Contradicted memories are blocked from being served as facts
                    c.status = .stale
                    c.updatedAt = Date()
                    db.saveMemoryCapsule(c)
                    continue
                }

                db.recordMemoryHit(id: c.id)
                results.append(c)
            }
        }
        return results
    }

    /// Formats a list of memory capsules into an ultra-dense Markdown block for agent injection.
    public static func formatMicroCapsules(
        _ capsules: [MemoryCapsule],
        project: String
    ) -> String {
        formatMicroCapsules(capsules, project: project, in: nil)
    }

    /// Formats a list of memory capsules into an ultra-dense Markdown block for agent injection,
    /// decorating parent directives with linked dead ends and subsuming child dead ends.
    static func formatMicroCapsules(
        _ capsules: [MemoryCapsule],
        project: String,
        in database: ActivityDatabase? = nil
    ) -> String {
        guard !capsules.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("### FLIGHTDECK CAUSAL MEMORY [\(project.uppercased())]")
        lines.append("> Deterministic rules and hazard traps verified in previous sessions:\n")

        // Subsume child dead-end capsules if parent capsules are present in the list
        var subsumedIds = Set<String>()
        if let db = database {
            for c in capsules where c.kind != .deadEnd {
                let deadEnds = db.fetchDeadEnds(for: c.id)
                for de in deadEnds {
                    subsumedIds.insert(de.id)
                }
            }
        }

        for c in capsules {
            if subsumedIds.contains(c.id) {
                continue
            }
            var directive = c.microDirective
            if let db = database, c.kind != .deadEnd {
                let deadEnds = db.fetchDeadEnds(for: c.id)
                if !deadEnds.isEmpty {
                    directive += "\n  ✕ KNOWN DEAD ENDS (Do not attempt):"
                    for de in deadEnds {
                        let reason = (de.failureSignature?.isEmpty == false) ? " -> Failed: \(de.failureSignature!)" : ""
                        directive += "\n    • Attempted: \(de.resolution)\(reason)"
                    }
                }
            }
            lines.append(directive)
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Re-verifies active capsules against current Git tree state.
    static func reverifyWithGit(
        project: String,
        cwd: String,
        in database: ActivityDatabase?
    ) -> (active: Int, unverified: Int, obsolete: Int) {
        guard let db = database else { return (0, 0, 0) }
        let currentSha = currentGitSha(cwd: cwd)
        let capsules = db.fetchMemoryCapsules(project: project, filePath: nil, status: nil)

        var activeCount = 0
        var unverifiedCount = 0
        var obsoleteCount = 0

        for var capsule in capsules {
            let fullPath = (cwd as NSString).appendingPathComponent(capsule.filePath)
            if !FileManager.default.fileExists(atPath: fullPath) {
                capsule.status = .obsolete
                capsule.updatedAt = Date()
                db.saveMemoryCapsule(capsule)
                obsoleteCount += 1
                continue
            }

            if let recordedHash = capsule.fileHash, let currentHash = computeFileHash(at: fullPath) {
                if recordedHash != currentHash && capsule.gitSha != currentSha {
                    capsule.status = .unverified
                    capsule.updatedAt = Date()
                    db.saveMemoryCapsule(capsule)
                    unverifiedCount += 1
                    continue
                }
            }

            if capsule.status == .active {
                activeCount += 1
            }
        }

        return (active: activeCount, unverified: unverifiedCount, obsolete: obsoleteCount)
    }

    /// Re-verifies stale dependents whose premise was superseded.
    /// If the dependent's target symbol and trigger pattern still hold in the repository code,
    /// and its invalidated premise has an active superseding replacement, it un-stales the dependent,
    /// rewires the DEPENDS_ON edge to the active replacement premise, and restores active status.
    static func reverifyStaleDependents(
        project: String,
        cwd: String,
        in database: ActivityDatabase?
    ) -> (recovered: Int, remainedStale: Int) {
        guard let db = database else { return (0, 0) }
        let allCapsules = db.fetchMemoryCapsules(project: project, filePath: nil, status: nil)
        let staleDependents = allCapsules.filter { $0.anchorStatus == .stale || $0.status == .stale }

        var recoveredCount = 0
        var remainedCount = 0

        for var capsule in staleDependents {
            let fullPath = (cwd as NSString).appendingPathComponent(capsule.filePath)
            guard FileManager.default.fileExists(atPath: fullPath),
                  let fileContent = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
                remainedCount += 1
                continue
            }

            let symbolHolds = capsule.symbol.map { fileContent.contains($0) } ?? true
            let triggerHolds = fileContent.contains(capsule.triggerPattern)

            if symbolHolds && triggerHolds {
                // Find DEPENDS_ON edges
                let depEdges = db.fetchMemoryEdges(fromId: capsule.id, type: .dependsOn)
                for edge in depEdges {
                    if let oldPremise = db.fetchMemoryCapsule(id: edge.toCapsuleId),
                       let replacementId = oldPremise.invalidatedBy,
                       let newPremise = db.fetchMemoryCapsule(id: replacementId),
                       newPremise.status == .active {
                        // Rewire DEPENDS_ON edge to active replacement premise
                        db.saveMemoryEdge(MemoryEdge(
                            fromCapsuleId: capsule.id,
                            toCapsuleId: newPremise.id,
                            edgeType: .dependsOn
                        ))
                    }
                }

                capsule.status = .active
                capsule.anchorStatus = .verified
                capsule.conflictNote = "✓ Re-verified: Claim re-affirmed against repository state."
                capsule.updatedAt = Date()
                db.saveMemoryCapsule(capsule)
                recoveredCount += 1
            } else {
                remainedCount += 1
            }
        }

        return (recovered: recoveredCount, remainedStale: remainedCount)
    }
}

// MARK: - Memory Federation & Git Team Sync

public struct MemoryFederation: Sendable {
    public static let defaultFederationPath = ".flightdeck/memory"

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parseDate(_ val: Any?) -> Date? {
        guard let s = val as? String else { return nil }
        if let d = isoFormatter.date(from: s) { return d }
        if let d = isoFallbackFormatter.date(from: s) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        if let d = df.date(from: s) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        return df.date(from: s)
    }

    /// Exports verified active and conflicted memory capsules and causal edges to line-delimited JSON (JSONL).
    /// Deterministically sorted to ensure minimal, noise-free Git diffs.
    /// Uses atomic writes (.tmp -> atomic replace) to prevent corruption.
    @discardableResult
    static func exportAtoms(
        to dirPath: String,
        project: String? = nil,
        in db: ActivityDatabase
    ) throws -> (atoms: Int, edges: Int) {
        let fm = FileManager.default
        let outUrl = URL(fileURLWithPath: dirPath)
        try fm.createDirectory(at: outUrl, withIntermediateDirectories: true)

        let allCapsules = db.fetchMemoryCapsules(project: project, filePath: nil, status: nil)
        var exportable = allCapsules.filter {
            ($0.status == .active || $0.status == .conflicted) && $0.authority != .L4
        }

        // Deterministic sort: filePath ASC, symbol ASC, triggerPattern ASC, id ASC
        exportable.sort { a, b in
            if a.filePath != b.filePath { return a.filePath < b.filePath }
            if (a.symbol ?? "") != (b.symbol ?? "") { return (a.symbol ?? "") < (b.symbol ?? "") }
            if a.triggerPattern != b.triggerPattern { return a.triggerPattern < b.triggerPattern }
            return a.id < b.id
        }

        let atomsUrl = outUrl.appendingPathComponent("atoms.jsonl")
        let tmpAtomsUrl = outUrl.appendingPathComponent("atoms.jsonl.tmp")

        var atomsOutput = ""
        for capsule in exportable {
            var dict: [String: Any] = [
                "id": capsule.id,
                "project": capsule.project,
                "file_path": capsule.filePath,
                "filePath": capsule.filePath,
                "kind": capsule.kind.rawValue,
                "authority": capsule.authority.rawValue,
                "trigger_pattern": capsule.triggerPattern,
                "triggerPattern": capsule.triggerPattern,
                "resolution": capsule.resolution,
                "source": capsule.source,
                "verified_by": capsule.verifiedBy,
                "occurrence_count": capsule.occurrenceCount,
                "git_sha": capsule.gitSha,
                "confidence": capsule.confidence,
                "hit_count": capsule.hitCount,
                "state": capsule.status.rawValue,
                "status": capsule.status.rawValue,
                "anchor_status": capsule.anchorStatus.rawValue,
                "valid_from": isoFormatter.string(from: capsule.validFrom),
                "recorded_at": isoFormatter.string(from: capsule.recordedAt),
                "created_at": isoFormatter.string(from: capsule.createdAt),
                "updated_at": isoFormatter.string(from: capsule.updatedAt),
            ]
            if let sym = capsule.symbol { dict["symbol"] = sym }
            if let subj = capsule.subject { dict["subject"] = subj }
            if let pred = capsule.predicate { dict["predicate"] = pred }
            if let obj = capsule.objectValue { dict["object_value"] = obj; dict["objectValue"] = obj }
            if let sig = capsule.failureSignature { dict["failure_signature"] = sig; dict["failureSignature"] = sig }
            if let note = capsule.conflictNote { dict["conflict_note"] = note; dict["conflictNote"] = note }
            if let hash = capsule.fileHash { dict["file_hash"] = hash; dict["fileHash"] = hash }
            if let sess = capsule.originSessionId { dict["session_id"] = sess; dict["sessionId"] = sess }
            if let until = capsule.validUntil { dict["valid_until"] = isoFormatter.string(from: until); dict["validUntil"] = isoFormatter.string(from: until) }
            if let trial = capsule.trialUntil { dict["trial_until"] = isoFormatter.string(from: trial); dict["trialUntil"] = isoFormatter.string(from: trial) }
            if let inv = capsule.invalidatedBy { dict["invalidated_by"] = inv; dict["invalidatedBy"] = inv }

            let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes])
            if let str = String(data: data, encoding: .utf8) {
                atomsOutput.append(str + "\n")
            }
        }
        try atomsOutput.write(to: tmpAtomsUrl, atomically: true, encoding: .utf8)
        _ = try? fm.removeItem(at: atomsUrl)
        try fm.moveItem(at: tmpAtomsUrl, to: atomsUrl)

        // Export active causal edges
        let exportableIds = Set(exportable.map { $0.id })
        let allEdges = db.fetchMemoryEdges()
        var exportableEdges = allEdges.filter {
            $0.validUntil == nil && exportableIds.contains($0.fromCapsuleId) && exportableIds.contains($0.toCapsuleId)
        }
        exportableEdges.sort { a, b in
            if a.fromCapsuleId != b.fromCapsuleId { return a.fromCapsuleId < b.fromCapsuleId }
            if a.toCapsuleId != b.toCapsuleId { return a.toCapsuleId < b.toCapsuleId }
            if a.edgeType.rawValue != b.edgeType.rawValue { return a.edgeType.rawValue < b.edgeType.rawValue }
            return a.id < b.id
        }

        let edgesUrl = outUrl.appendingPathComponent("edges.jsonl")
        let tmpEdgesUrl = outUrl.appendingPathComponent("edges.jsonl.tmp")
        var edgesOutput = ""
        for edge in exportableEdges {
            var dict: [String: Any] = [
                "id": edge.id,
                "from_atom_id": edge.fromCapsuleId,
                "fromCapsuleId": edge.fromCapsuleId,
                "to_atom_id": edge.toCapsuleId,
                "toCapsuleId": edge.toCapsuleId,
                "edge_type": edge.edgeType.rawValue,
                "edgeType": edge.edgeType.rawValue,
                "valid_from": isoFormatter.string(from: edge.validFrom),
                "recorded_at": isoFormatter.string(from: edge.recordedAt),
            ]
            if let until = edge.validUntil { dict["valid_until"] = isoFormatter.string(from: until); dict["validUntil"] = isoFormatter.string(from: until) }
            if let inv = edge.invalidatedBy { dict["invalidated_by"] = inv; dict["invalidatedBy"] = inv }

            let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes])
            if let str = String(data: data, encoding: .utf8) {
                edgesOutput.append(str + "\n")
            }
        }
        try edgesOutput.write(to: tmpEdgesUrl, atomically: true, encoding: .utf8)
        _ = try? fm.removeItem(at: edgesUrl)
        try fm.moveItem(at: tmpEdgesUrl, to: edgesUrl)

        return (exportable.count, exportableEdges.count)
    }

    /// Imports memory capsules and causal edges from .flightdeck/memory JSONL files.
    /// Runs write-side adjudication on incoming atoms so slot conflicts are preserved safely.
    static func importAtoms(
        from dirPath: String,
        project: String? = nil,
        in db: ActivityDatabase
    ) throws -> (imported: Int, updated: Int, conflicts: Int, skipped: Int, edges: Int) {
        let fm = FileManager.default
        let inUrl = URL(fileURLWithPath: dirPath)
        let atomsUrl = inUrl.appendingPathComponent("atoms.jsonl")
        let edgesUrl = inUrl.appendingPathComponent("edges.jsonl")

        guard fm.fileExists(atPath: atomsUrl.path) else {
            return (0, 0, 0, 0, 0)
        }

        let atomsContent = try String(contentsOf: atomsUrl, encoding: .utf8)
        let lines = atomsContent.components(separatedBy: .newlines)

        var imported = 0
        var updated = 0
        var conflicts = 0
        var skipped = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let atomProject = dict["project"] as? String ?? "default"
            if let project, !project.isEmpty, atomProject != project {
                skipped += 1
                continue
            }

            let id = dict["id"] as? String ?? UUID().uuidString
            let filePath = dict["file_path"] as? String ?? dict["filePath"] as? String ?? ""
            let symbol = dict["symbol"] as? String
            let subject = dict["subject"] as? String
            let predicate = dict["predicate"] as? String
            let objectValue = dict["object_value"] as? String ?? dict["objectValue"] as? String
            let kind = MemoryKind(rawValue: dict["kind"] as? String ?? "rule") ?? .rule
            let authority = AuthorityLevel(rawValue: dict["authority"] as? String ?? "L2") ?? .L2
            let triggerPattern = dict["trigger_pattern"] as? String ?? dict["triggerPattern"] as? String ?? ""
            let failureSignature = dict["failure_signature"] as? String ?? dict["failureSignature"] as? String
            let resolution = dict["resolution"] as? String ?? ""
            let originSessionId = dict["session_id"] as? String ?? dict["sessionId"] as? String ?? dict["originSessionId"] as? String
            let source = dict["source"] as? String ?? "agent"
            let verifiedBy = dict["verified_by"] as? String ?? dict["verifiedBy"] as? String ?? "compiler"
            let occurrenceCount = dict["occurrence_count"] as? Int ?? dict["occurrenceCount"] as? Int ?? 1
            let gitSha = dict["git_sha"] as? String ?? dict["gitSha"] as? String ?? "HEAD"
            let fileHash = dict["file_hash"] as? String ?? dict["fileHash"] as? String
            let confidence = (dict["confidence"] as? NSNumber)?.doubleValue ?? 1.0
            let hitCount = dict["hit_count"] as? Int ?? dict["hitCount"] as? Int ?? 0
            let status = MemoryStatus(rawValue: dict["state"] as? String ?? dict["status"] as? String ?? "active") ?? .active
            let anchorStatus = AnchorStatus(rawValue: dict["anchor_status"] as? String ?? dict["anchorStatus"] as? String ?? "unverified") ?? .unverified
            let conflictNote = dict["conflict_note"] as? String ?? dict["conflictNote"] as? String
            let validFrom = parseDate(dict["valid_from"] ?? dict["validFrom"]) ?? Date()
            let validUntil = parseDate(dict["valid_until"] ?? dict["validUntil"])
            let trialUntil = parseDate(dict["trial_until"] ?? dict["trialUntil"])
            let recordedAt = parseDate(dict["recorded_at"] ?? dict["recordedAt"]) ?? Date()
            let invalidatedBy = dict["invalidated_by"] as? String ?? dict["invalidatedBy"] as? String
            let createdAt = parseDate(dict["created_at"] ?? dict["createdAt"]) ?? Date()
            let updatedAt = parseDate(dict["updated_at"] ?? dict["updatedAt"]) ?? Date()

            var capsule = MemoryCapsule(
                id: id,
                project: atomProject,
                filePath: filePath,
                symbol: symbol,
                subject: subject,
                predicate: predicate,
                objectValue: objectValue,
                kind: kind,
                authority: authority,
                triggerPattern: triggerPattern,
                failureSignature: failureSignature,
                resolution: resolution,
                originSessionId: originSessionId,
                source: source,
                verifiedBy: verifiedBy,
                occurrenceCount: occurrenceCount,
                gitSha: gitSha,
                fileHash: fileHash,
                confidence: confidence,
                hitCount: hitCount,
                status: status,
                anchorStatus: anchorStatus,
                conflictNote: conflictNote,
                validFrom: validFrom,
                validUntil: validUntil,
                trialUntil: trialUntil,
                recordedAt: recordedAt,
                invalidatedBy: invalidatedBy,
                createdAt: createdAt,
                updatedAt: updatedAt
            )

            if let existing = db.fetchMemoryCapsule(id: id) {
                if capsule.authority.trustScore > existing.authority.trustScore || capsule.updatedAt > existing.updatedAt {
                    db.saveMemoryCapsule(capsule)
                    updated += 1
                } else {
                    skipped += 1
                }
            } else {
                let (persisted, _) = CausalMemoryEngine.adjudicate(newCapsule: &capsule, in: db)
                if persisted.status == .conflicted {
                    conflicts += 1
                } else {
                    imported += 1
                }
            }
        }

        // Import edges
        var edgesImported = 0
        if fm.fileExists(atPath: edgesUrl.path),
           let edgesContent = try? String(contentsOf: edgesUrl, encoding: .utf8) {
            let edgeLines = edgesContent.components(separatedBy: .newlines)
            for line in edgeLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let data = trimmed.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let id = dict["id"] as? String ?? UUID().uuidString
                let fromId = dict["from_atom_id"] as? String ?? dict["fromCapsuleId"] as? String ?? ""
                let toId = dict["to_atom_id"] as? String ?? dict["toCapsuleId"] as? String ?? ""
                let edgeTypeRaw = dict["edge_type"] as? String ?? dict["edgeType"] as? String ?? "SOLVES"
                let edgeType = CausalEdgeType(rawValue: edgeTypeRaw) ?? .solves
                let validFrom = parseDate(dict["valid_from"] ?? dict["validFrom"]) ?? Date()
                let validUntil = parseDate(dict["valid_until"] ?? dict["validUntil"])
                let recordedAt = parseDate(dict["recorded_at"] ?? dict["recordedAt"]) ?? Date()
                let invalidatedBy = dict["invalidated_by"] as? String ?? dict["invalidatedBy"] as? String

                if db.fetchMemoryCapsule(id: fromId) != nil && db.fetchMemoryCapsule(id: toId) != nil {
                    let edge = MemoryEdge(
                        id: id,
                        fromCapsuleId: fromId,
                        toCapsuleId: toId,
                        edgeType: edgeType,
                        validFrom: validFrom,
                        validUntil: validUntil,
                        recordedAt: recordedAt,
                        invalidatedBy: invalidatedBy
                    )
                    db.saveMemoryEdge(edge)
                    edgesImported += 1
                }
            }
        }

        return (imported, updated, conflicts, skipped, edgesImported)
    }

    /// Two-way sync: imports team memories from .flightdeck/memory and exports local verified memories.
    static func sync(
        repoRoot: String = ".",
        project: String? = nil,
        in db: ActivityDatabase
    ) throws -> (imported: Int, updated: Int, conflicts: Int, exportedAtoms: Int, exportedEdges: Int) {
        let federationDir = (repoRoot as NSString).appendingPathComponent(defaultFederationPath)
        let importRes = try importAtoms(from: federationDir, project: project, in: db)
        let exportRes = try exportAtoms(to: federationDir, project: project, in: db)
        return (importRes.imported, importRes.updated, importRes.conflicts, exportRes.atoms, exportRes.edges)
    }

    /// Installs git post-merge and post-checkout hooks to automatically sync causal memories on pull/checkout.
    @discardableResult
    public static func installGitHooks(in repoRoot: String = ".") throws -> Bool {
        let fm = FileManager.default
        let hooksDir = (repoRoot as NSString).appendingPathComponent(".git/hooks")
        guard fm.fileExists(atPath: hooksDir) else {
            return false
        }

        let script = """
        #!/bin/sh
        # Flightdeck Causal Memory Sync Hook
        if [ -d ".flightdeck/memory" ]; then
            if command -v flightdeck >/dev/null 2>&1; then
                flightdeck memory import >/dev/null 2>&1 || true
            elif [ -f "substrate/src/ecs/cli.py" ] && command -v python3 >/dev/null 2>&1; then
                python3 -m substrate.src.ecs.cli import >/dev/null 2>&1 || true
            fi
        fi
        """

        let hookNames = ["post-merge", "post-checkout"]
        for hook in hookNames {
            let hookPath = (hooksDir as NSString).appendingPathComponent(hook)
            if fm.fileExists(atPath: hookPath) {
                let existing = (try? String(contentsOfFile: hookPath, encoding: .utf8)) ?? ""
                if !existing.contains("Flightdeck Causal Memory") {
                    let updated = existing + "\n" + script + "\n"
                    try updated.write(toFile: hookPath, atomically: true, encoding: .utf8)
                }
            } else {
                try script.write(toFile: hookPath, atomically: true, encoding: .utf8)
            }
            // Set executable permission 0755
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
        }
        return true
    }
}
