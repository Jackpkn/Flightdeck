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
    case L0 = "L0" // Filesystem/git state (Ground truth, read-only)
    case L1 = "L1" // Direct machine ground truth: AST symbols, compiler exit code, test pass (High, read-only)
    case L2 = "L2" // Agent observations & transcript miner candidate hypotheses (Medium, writable)
    case L3 = "L3" // User explicit directive (High user intent, writable)
    case L4 = "L4" // External document/web (Low, quarantined)

    public var isQuarantined: Bool {
        self == .L4
    }

    public var trustScore: Double {
        switch self {
        case .L0: return 1.0
        case .L1: return 0.95
        case .L3: return 0.85
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
    public var recordedAt: Date
    public var invalidatedBy: String?
    public var createdAt: Date
    public var updatedAt: Date

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
        if let conflictNote, !conflictNote.isEmpty {
            return "[CONFLICT: \(subject ?? symbol ?? filePath)]\n⚠️ Two sources disagree on this code region:\n\(conflictNote)\n  Review code before proceeding."
        }
        if anchorStatus == .stale || status == .stale {
            return "[STALE: `\(filePath)`]\n  ⚠️ Code changed since this was written; verify before trusting.\n  Trigger: \(triggerPattern)\n  Prior Fix: \(resolution)"
        }
        let verifiedTag = (anchorStatus == .verified) ? " (verified against committed code)" : ""
        var out = "\(kind.badge): `\(filePath)`\(verifiedTag)"
        if let symbol, !symbol.isEmpty {
            out += " (symbol: \(symbol))"
        }
        out += "\n  Trigger: \(triggerPattern)"
        if let failureSignature, !failureSignature.isEmpty {
            out += "\n  Failure: \(failureSignature)"
        }
        out += "\n  Resolution: \(resolution)"
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
        guard !capsules.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("### FLIGHTDECK CAUSAL MEMORY [\(project.uppercased())]")
        lines.append("> Deterministic rules and hazard traps verified in previous sessions:\n")
        for c in capsules {
            lines.append(c.microDirective)
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
