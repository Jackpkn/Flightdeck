import Foundation
import GRDB

/// One closed stretch of time in one app, as stored on disk.
struct AppActivityRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "app_activity"

    var id: Int64?
    var appName: String
    var bundleId: String
    var windowTitle: String?
    var startedAt: Date
    var endedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// SQLite-backed store for app-activity segments, in Application Support so it
/// survives restarts and accumulates across days. Only *closed* segments are
/// written — the in-flight one lives in memory until the user switches away.
final class ActivityDatabase {
    private let dbQueue: DatabaseQueue

    static let shared: ActivityDatabase? = {
        do {
            return try ActivityDatabase()
        } catch {
            print("ActivityDatabase: could not open — \(error)")
            return nil
        }
    }()

    init(inMemory: Bool = false) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Flightdeck", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: support.appendingPathComponent("flightdeck.sqlite").path)
        }
        try Self.migrator.migrate(dbQueue)
    }

    static func inMemory() throws -> ActivityDatabase {
        try ActivityDatabase(inMemory: true)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createAppActivity") { db in
            try db.create(table: AppActivityRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("appName", .text).notNull()
                t.column("bundleId", .text).notNull()
                t.column("windowTitle", .text)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime).notNull()
            }
            try db.create(
                index: "app_activity_on_startedAt",
                on: AppActivityRecord.databaseTableName,
                columns: ["startedAt"]
            )
        }

        // Phase 1: Claude Code statusline → live session snapshots
        migrator.registerMigration("addSessionLive") { db in
            try db.create(table: SessionLiveRecord.databaseTableName) { t in
                t.column("sessionId", .text).primaryKey()
                t.column("project", .text).notNull().defaults(to: "")
                t.column("branch", .text).notNull().defaults(to: "")
                t.column("model", .text).notNull().defaults(to: "")
                t.column("contextTokens", .integer).notNull().defaults(to: 0)
                t.column("totalCostUsd", .double).notNull().defaults(to: 0)
                t.column("lastFile", .text).notNull().defaults(to: "")
                t.column("updatedAt", .datetime).notNull()
            }
        }

        // Phase 1: Claude Code hooks → AI event stream
        migrator.registerMigration("addAiEvents") { db in
            try db.create(table: AIEventRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .text).notNull()
                t.column("event", .text).notNull()
                t.column("toolName", .text)
                t.column("detail", .text)
                t.column("timestamp", .datetime).notNull()
            }
            try db.create(
                index: "ai_events_on_sessionId",
                on: AIEventRecord.databaseTableName,
                columns: ["sessionId"]
            )
            try db.create(
                index: "ai_events_on_timestamp",
                on: AIEventRecord.databaseTableName,
                columns: ["timestamp"]
            )
        }

        // Add dynamic context window size from statusline JSON
        migrator.registerMigration("addContextTotalTokens") { db in
            try db.alter(table: SessionLiveRecord.databaseTableName) { t in
                t.add(column: "contextTotalTokens", .integer).notNull().defaults(to: 200_000)
            }
        }

        // Epistemic Causal Substrate (ECS) - Causal Memory Capsules
        migrator.registerMigration("addMemoryCapsules") { db in
            try db.create(table: MemoryCapsule.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("project", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("symbol", .text)
                t.column("kind", .text).notNull()
                t.column("triggerPattern", .text).notNull()
                t.column("failureSignature", .text)
                t.column("resolution", .text).notNull()
                t.column("originSessionId", .text)
                t.column("gitSha", .text).notNull()
                t.column("fileHash", .text)
                t.column("confidence", .double).notNull().defaults(to: 1.0)
                t.column("hitCount", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_memory_project_path",
                on: MemoryCapsule.databaseTableName,
                columns: ["project", "filePath"]
            )
            try db.create(
                index: "idx_memory_status",
                on: MemoryCapsule.databaseTableName,
                columns: ["status"]
            )
        }

        // Causal edges table for bitemporal graph & recursive CTE
        migrator.registerMigration("addCausalEdges") { db in
            try db.create(table: MemoryEdge.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("fromCapsuleId", .text).notNull()
                t.column("toCapsuleId", .text).notNull()
                t.column("edgeType", .text).notNull()
                t.column("validFrom", .datetime).notNull()
                t.column("validUntil", .datetime)
                t.column("recordedAt", .datetime).notNull()
                t.column("invalidatedBy", .text)
            }
            try db.create(
                index: "idx_edges_from",
                on: MemoryEdge.databaseTableName,
                columns: ["fromCapsuleId"]
            )
            try db.create(
                index: "idx_edges_to",
                on: MemoryEdge.databaseTableName,
                columns: ["toCapsuleId"]
            )
            try db.create(
                index: "idx_edges_type",
                on: MemoryEdge.databaseTableName,
                columns: ["edgeType"]
            )
        }

        // Add Causal Bitemporal & Anchor Fields to MemoryCapsules
        migrator.registerMigration("addCapsuleCausalFields") { db in
            try db.alter(table: MemoryCapsule.databaseTableName) { t in
                t.add(column: "subject", .text)
                t.add(column: "predicate", .text)
                t.add(column: "objectValue", .text)
                t.add(column: "authority", .text).notNull().defaults(to: "L2")
                t.add(column: "anchorStatus", .text).notNull().defaults(to: "unverified")
                t.add(column: "conflictNote", .text)
                t.add(column: "validFrom", .datetime)
                t.add(column: "validUntil", .datetime)
                t.add(column: "recordedAt", .datetime)
                t.add(column: "invalidatedBy", .text)
            }
        }

        // Add source and occurrenceCount for candidate hypothesis & double-verification promotion
        migrator.registerMigration("addCapsuleSourceAndOccurrence") { db in
            try db.alter(table: MemoryCapsule.databaseTableName) { t in
                t.add(column: "source", .text).notNull().defaults(to: "agent")
                t.add(column: "occurrenceCount", .integer).notNull().defaults(to: 1)
            }
        }

        // Add verifiedBy for deterministic provenance tracking (Gate 1 compiler, Gate 4 host_agent, human)
        migrator.registerMigration("addCapsuleVerifiedBy") { db in
            try db.alter(table: MemoryCapsule.databaseTableName) { t in
                t.add(column: "verifiedBy", .text).notNull().defaults(to: "compiler")
            }
        }

        // Add trialUntil for provisional host-agent adjudication trial periods
        migrator.registerMigration("addCapsuleTrialUntil") { db in
            try db.alter(table: MemoryCapsule.databaseTableName) { t in
                t.add(column: "trialUntil", .datetime)
            }
        }

        // Add efficacy counters and feedback tracking for closed-loop self-calibration
        migrator.registerMigration("addCapsuleEfficacyAndFeedback") { db in
            try db.alter(table: MemoryCapsule.databaseTableName) { t in
                t.add(column: "successCount", .integer).notNull().defaults(to: 0)
                t.add(column: "failureCount", .integer).notNull().defaults(to: 0)
                t.add(column: "lastFeedbackAt", .datetime)
            }
        }

        // Add verificationCmd for active executable test harness during dream consolidation
        migrator.registerMigration("addCapsuleVerificationCmd") { db in
            try db.alter(table: MemoryCapsule.databaseTableName) { t in
                t.add(column: "verificationCmd", .text)
            }
        }

        return migrator
    }


    func save(appName: String, bundleId: String, windowTitle: String?, startedAt: Date, endedAt: Date) {
        // Sub-second blips are switch-through noise, not real usage.
        guard endedAt.timeIntervalSince(startedAt) >= 1 else { return }
        do {
            try dbQueue.write { db in
                var record = AppActivityRecord(
                    id: nil,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: windowTitle,
                    startedAt: startedAt,
                    endedAt: endedAt
                )
                try record.insert(db)
            }
        } catch {
            print("ActivityDatabase: save failed — \(error)")
        }
    }

    /// Individual segments for one day, in order — the timeline needs exact
    /// start/end pairs, not the aggregate.
    func segments(on day: Date) -> [AppSegment] {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        do {
            let records: [AppActivityRecord] = try dbQueue.read { db in
                try AppActivityRecord
                    .filter(Column("startedAt") >= start && Column("startedAt") < end)
                    .order(Column("startedAt"))
                    .fetchAll(db)
            }
            return records.map {
                AppSegment(
                    id: "\($0.id ?? 0)",
                    appName: $0.appName,
                    bundleId: $0.bundleId,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt
                )
            }
        } catch {
            print("ActivityDatabase: segments failed — \(error)")
            return []
        }
    }

    /// Total seconds per app since `date`, aggregated in SQL rather than by
    /// loading every row into memory.
    func totals(since date: Date) -> [(name: String, seconds: TimeInterval, bundleId: String)] {
        do {
            return try dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT appName,
                           bundleId,
                           SUM(strftime('%s', endedAt) - strftime('%s', startedAt)) AS seconds
                    FROM app_activity
                    WHERE startedAt >= ?
                    GROUP BY appName
                    ORDER BY seconds DESC
                    """, arguments: [date])
                return rows.map { row in
                    (
                        name: row["appName"] as String,
                        seconds: TimeInterval(row["seconds"] as Double? ?? 0),
                        bundleId: row["bundleId"] as String
                    )
                }
            }
        } catch {
            print("ActivityDatabase: totals failed — \(error)")
            return []
        }
    }

    // MARK: - Claude Code Integration: Session Live

    /// Expose the underlying reader for GRDB `ValueObservation` from the GUI.
    var reader: any DatabaseReader { dbQueue }

    /// Upsert a live session record — called by the `flightdeck statusline` CLI.
    func upsertSession(_ record: SessionLiveRecord) {
        var cleanRecord = record
        cleanRecord.lastFile = SecretRedactor.shared.redact(record.lastFile)
        do {
            try dbQueue.write { db in
                try cleanRecord.save(db, onConflict: .replace)
            }
        } catch {
            print("ActivityDatabase: upsertSession failed — \(error)")
        }
    }

    /// Fetch all live sessions, most recently updated first.
    func fetchLiveSessions() -> [SessionLiveRecord] {
        do {
            return try dbQueue.read { db in
                try SessionLiveRecord
                    .order(Column("updatedAt").desc)
                    .fetchAll(db)
            }
        } catch {
            print("ActivityDatabase: fetchLiveSessions failed — \(error)")
            return []
        }
    }

    // MARK: - Claude Code Integration: AI Events

    /// Insert a hook event — called by the `flightdeck hook` CLI.
    func insertEvent(_ record: AIEventRecord) {
        var cleanRecord = record
        if let tool = cleanRecord.toolName {
            cleanRecord.toolName = SecretRedactor.shared.redact(tool)
        }
        if let detail = cleanRecord.detail {
            cleanRecord.detail = SecretRedactor.shared.redact(detail)
        }

        do {
            try dbQueue.write { db in
                var mutable = cleanRecord
                try mutable.insert(db)
            }
        } catch {
            print("ActivityDatabase: insertEvent failed — \(error)")
        }
    }

    /// Fetch recent AI events for the activity feed. Capped at `limit`.
    func recentEvents(limit: Int = 100) -> [AIEventRecord] {
        do {
            return try dbQueue.read { db in
                try AIEventRecord
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        } catch {
            print("ActivityDatabase: recentEvents failed — \(error)")
            return []
        }
    }

    // MARK: - Epistemic Causal Memory (ECS)

    /// Saves or updates a causal memory capsule.
    func saveMemoryCapsule(_ capsule: MemoryCapsule) {
        do {
            try dbQueue.write { db in
                try capsule.save(db)
            }
        } catch {
            print("ActivityDatabase: saveMemoryCapsule failed — \(error)")
        }
    }

    /// Fetches memory capsules filtered by optional project, file path, and status.
    func fetchMemoryCapsules(
        project: String? = nil,
        filePath: String? = nil,
        status: MemoryStatus? = nil
    ) -> [MemoryCapsule] {
        do {
            return try dbQueue.read { db in
                var query = MemoryCapsule.all()
                if let project, !project.isEmpty {
                    query = query.filter(Column("project") == project)
                }
                if let filePath, !filePath.isEmpty {
                    query = query.filter(Column("filePath") == filePath)
                }
                if let status {
                    query = query.filter(Column("status") == status.rawValue)
                }
                return try query.order(Column("updatedAt").desc).fetchAll(db)
            }
        } catch {
            print("ActivityDatabase: fetchMemoryCapsules failed — \(error)")
            return []
        }
    }

    /// Fetches a single memory capsule by ID.
    func fetchMemoryCapsule(id: String) -> MemoryCapsule? {
        do {
            return try dbQueue.read { db in
                try MemoryCapsule.fetchOne(db, key: id)
            }
        } catch {
            return nil
        }
    }

    /// Fetches the count of capsules awaiting Gate 4 host-agent adjudication.
    func fetchPendingAdjudicationCount(project: String? = nil) -> Int {
        do {
            return try dbQueue.read { db in
                var query = MemoryCapsule.filter(Column("status") == "pending_adjudication")
                if let project {
                    query = query.filter(Column("project") == project)
                }
                return try query.fetchCount(db)
            }
        } catch {
            return 0
        }
    }

    /// Records that an agent consulted or benefited from this capsule.
    func recordMemoryHit(id: String) {
        do {
            try dbQueue.write { db in
                if var capsule = try MemoryCapsule.fetchOne(db, key: id) {
                    capsule.hitCount += 1
                    capsule.updatedAt = Date()
                    try capsule.update(db)
                }
            }
        } catch {
            print("ActivityDatabase: recordMemoryHit failed — \(error)")
        }
    }

    struct FeedbackResult: Equatable {
        let updatedCount: Int
        let demotedCount: Int
        let demotedIds: [String]
    }

    /// Records outcome feedback (success or failure) for retrieved memory capsules.
    /// Adjusts confidence, increments success/failure counts, and demotes low-efficacy capsules.
    @discardableResult
    func recordFeedback(
        atomIds: [String],
        outcome: String,
        errorSignature: String? = nil,
        note: String? = nil
    ) -> FeedbackResult {
        let clean = outcome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isSuccess = (clean == "success" || clean == "pass" || clean == "passed" || clean == "true" || clean == "1")
        var updatedCount = 0
        var demotedIds: [String] = []

        do {
            try dbQueue.write { db in
                for id in atomIds {
                    guard var capsule = try MemoryCapsule.fetchOne(db, key: id) else { continue }
                    if isSuccess {
                        capsule.successCount += 1
                        capsule.confidence = min(1.0, ((capsule.confidence + 0.05) * 100).rounded() / 100)
                    } else {
                        capsule.failureCount += 1
                        capsule.confidence = max(0.1, ((capsule.confidence - 0.15) * 100).rounded() / 100)
                        if capsule.confidence < 0.35 || (capsule.failureCount >= 3 && capsule.successCount == 0) {
                            capsule.status = .pendingAdjudication
                            let msg = "Demoted due to low efficacy: \(capsule.failureCount) failure(s), confidence \(capsule.confidence)"
                            if let errorSignature, !errorSignature.isEmpty {
                                capsule.conflictNote = (capsule.conflictNote != nil) ? "\(capsule.conflictNote!); \(msg) (Error: \(errorSignature.prefix(80)))" : "\(msg) (Error: \(errorSignature.prefix(80)))"
                            } else {
                                capsule.conflictNote = (capsule.conflictNote != nil) ? "\(capsule.conflictNote!); \(msg)" : msg
                            }
                            demotedIds.append(capsule.id)
                        }
                    }
                    capsule.lastFeedbackAt = Date()
                    capsule.updatedAt = Date()
                    try capsule.update(db)
                    updatedCount += 1
                }
            }
        } catch {
            print("ActivityDatabase: recordFeedback failed — \(error)")
        }

        return FeedbackResult(updatedCount: updatedCount, demotedCount: demotedIds.count, demotedIds: demotedIds)
    }

    /// Deletes a memory capsule by ID.
    @discardableResult
    func deleteMemoryCapsule(id: String) -> Bool {
        do {
            return try dbQueue.write { db in
                try MemoryCapsule.deleteOne(db, key: id)
            }
        } catch {
            print("ActivityDatabase: deleteMemoryCapsule failed — \(error)")
            return false
        }
    }

    /// Saves or updates a causal edge.
    func saveMemoryEdge(_ edge: MemoryEdge) {
        do {
            try dbQueue.write { db in
                try edge.save(db)
            }
        } catch {
            print("ActivityDatabase: saveMemoryEdge failed — \(error)")
        }
    }

    /// Fetches memory edges filtered by endpoints and type.
    func fetchMemoryEdges(
        fromId: String? = nil,
        toId: String? = nil,
        type: CausalEdgeType? = nil
    ) -> [MemoryEdge] {
        do {
            return try dbQueue.read { db in
                var query = MemoryEdge.all()
                if let fromId {
                    query = query.filter(Column("fromCapsuleId") == fromId)
                }
                if let toId {
                    query = query.filter(Column("toCapsuleId") == toId)
                }
                if let type {
                    query = query.filter(Column("edgeType") == type.rawValue)
                }
                return try query.fetchAll(db)
            }
        } catch {
            print("ActivityDatabase: fetchMemoryEdges failed — \(error)")
            return []
        }
    }

    /// Records a falsified hypothesis (dead end) and optionally links to a parent trap or rule
    /// via a typed LEADS_TO_DEAD_END causal edge.
    @discardableResult
    func recordDeadEnd(
        parentId: String? = nil,
        filePath: String,
        attemptedFix: String,
        failureSignature: String? = nil,
        triggerPattern: String = "",
        symbol: String? = nil,
        project: String = "Flightdeck",
        authority: AuthorityLevel = .L2
    ) -> (capsule: MemoryCapsule, edge: MemoryEdge?) {
        let deadEnd = MemoryCapsule(
            id: UUID().uuidString,
            project: project,
            filePath: filePath,
            symbol: symbol,
            kind: .deadEnd,
            authority: authority,
            triggerPattern: triggerPattern.isEmpty ? "Attempted: \(attemptedFix)" : triggerPattern,
            failureSignature: failureSignature,
            resolution: attemptedFix,
            verifiedBy: "compiler",
            status: .active,
            anchorStatus: .verified
        )
        saveMemoryCapsule(deadEnd)

        var edge: MemoryEdge? = nil
        if let parentId, !parentId.isEmpty {
            let createdEdge = MemoryEdge(
                id: UUID().uuidString,
                fromCapsuleId: parentId,
                toCapsuleId: deadEnd.id,
                edgeType: .leadsToDeadEnd
            )
            saveMemoryEdge(createdEdge)
            edge = createdEdge
        }
        return (deadEnd, edge)
    }

    /// Fetches all dead ends linked to a parent memory capsule via LEADS_TO_DEAD_END edges.
    func fetchDeadEnds(for parentCapsuleId: String) -> [MemoryCapsule] {
        let edges = fetchMemoryEdges(fromId: parentCapsuleId, type: .leadsToDeadEnd)
        return edges.compactMap { fetchMemoryCapsule(id: $0.toCapsuleId) }
    }

    struct BlastRadiusResult: Equatable {
        let nodes: [String]
        let truncated: Bool
        let totalEstimate: Int

        init(nodes: [String], truncated: Bool, totalEstimate: Int) {
            self.nodes = nodes
            self.truncated = truncated
            self.totalEstimate = totalEstimate
        }
    }

    /// Computes causal blast radius using SQLite recursive CTE over causal edges.
    /// Traverses outgoing dependencies/causes and incoming solutions (fix -> problem).
    /// Orders deterministically by MIN(depth) ASC, id ASC and returns truncation metrics.
    func computeBlastRadiusDetails(capsuleId: String, maxDepth: Int = 3, limit: Int = 100) -> BlastRadiusResult {
        do {
            return try dbQueue.read { db in
                let sql = """
                WITH RECURSIVE blast(id, depth) AS (
                    SELECT ? as id, 0 as depth
                    UNION
                    -- Forward causal, dependency, solution, and dead-end propagation
                    SELECT e.toCapsuleId, blast.depth + 1
                    FROM memory_edges e
                    JOIN blast ON e.fromCapsuleId = blast.id
                    WHERE e.edgeType IN ('DEPENDS_ON', 'CAUSES', 'SOLVES', 'LEADS_TO_DEAD_END')
                      AND (e.validUntil IS NULL OR e.validUntil > datetime('now'))
                      AND blast.depth < ?
                    UNION
                    -- Reverse resolution & causation traversal:
                    -- When seeded with a problem/trap, find the fix that SOLVES it (fix -> problem).
                    -- When seeded with an effect, find the root cause (cause -> effect).
                    SELECT e.fromCapsuleId, blast.depth + 1
                    FROM memory_edges e
                    JOIN blast ON e.toCapsuleId = blast.id
                    WHERE e.edgeType IN ('SOLVES', 'CAUSES')
                      AND (e.validUntil IS NULL OR e.validUntil > datetime('now'))
                      AND blast.depth < ?
                )
                -- Deterministic ordering: primary key MIN(depth) ASC, secondary key id ASC to eliminate depth-boundary ties
                SELECT id, MIN(depth) as min_depth
                FROM blast
                WHERE id != ?
                GROUP BY id
                ORDER BY min_depth ASC, id ASC;
                """
                let rows = try Row.fetchAll(db, sql: sql, arguments: [capsuleId, maxDepth, maxDepth, capsuleId])
                let total = rows.count
                let truncated = total > limit
                let nodes = rows.prefix(limit).compactMap { $0["id"] as? String }
                return BlastRadiusResult(nodes: nodes, truncated: truncated, totalEstimate: total)
            }
        } catch {
            print("ActivityDatabase: computeBlastRadius failed — \(error)")
            return BlastRadiusResult(nodes: [], truncated: false, totalEstimate: 0)
        }
    }

    /// Computes causal blast radius using SQLite recursive CTE over causal edges.
    /// Traverses outgoing dependencies/causes and incoming solutions (fix -> problem).
    func computeBlastRadius(capsuleId: String, maxDepth: Int = 3, limit: Int = 100) -> [String] {
        return computeBlastRadiusDetails(capsuleId: capsuleId, maxDepth: maxDepth, limit: limit).nodes
    }

    /// Compacts tombstones older than retention floor, and archives unresolved conflicts older than maxConflictAgeDays (default: 90 days).
    func compactTombstones(retentionDays: Int = 7, maxConflictAgeDays: Int = 90) -> (purgedTombstones: Int, archivedConflicts: Int) {
        do {
            return try dbQueue.write { db in
                let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
                let conflictCutoff = Calendar.current.date(byAdding: .day, value: -maxConflictAgeDays, to: Date()) ?? Date()

                // 1. Archive unresolved equal-authority conflicts older than 90 days to obsolete
                try db.execute(sql: """
                    UPDATE memory_capsules
                    SET status = 'obsolete',
                        conflictNote = COALESCE(conflictNote, '') || ' [Archived: unresolved after 90 days]',
                        updatedAt = ?
                    WHERE status = 'conflicted'
                      AND updatedAt < ?
                """, arguments: [Date(), conflictCutoff])
                let conflictCount = db.changesCount

                // 2. Prune tombstones past retention floor
                let countBefore = try MemoryCapsule.filter(Column("status") == "superseded" || Column("status") == "stale" || Column("status") == "obsolete")
                    .filter(Column("updatedAt") < cutoff)
                    .fetchCount(db)
                try db.execute(sql: """
                    DELETE FROM memory_capsules
                    WHERE status IN ('superseded', 'stale', 'obsolete')
                      AND updatedAt < ?
                """, arguments: [cutoff])
                return (countBefore, conflictCount)
            }
        } catch {
            print("ActivityDatabase: compactTombstones failed — \(error)")
            return (0, 0)
        }
    }

    // MARK: - Retention & Pruning

    public struct PruneResult: Equatable, Sendable {
        public let deletedActivityCount: Int
        public let deletedEventsCount: Int
        public let deletedLiveSessionsCount: Int
        public let bytesReclaimed: Int64

        public var totalDeletedRows: Int {
            deletedActivityCount + deletedEventsCount + deletedLiveSessionsCount
        }
    }

    /// Prunes activity and event records older than `days`.
    @discardableResult
    func prune(olderThanDays days: Int, vacuumAfter: Bool = true) throws -> PruneResult {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let sizeBefore = databaseSizeBytes()

        var deletedActivity = 0
        var deletedEvents = 0
        var deletedLive = 0

        try dbQueue.write { db in
            deletedActivity = try AppActivityRecord
                .filter(Column("startedAt") < cutoff)
                .deleteAll(db)

            deletedEvents = try AIEventRecord
                .filter(Column("timestamp") < cutoff)
                .deleteAll(db)

            deletedLive = try SessionLiveRecord
                .filter(Column("updatedAt") < cutoff)
                .deleteAll(db)
        }

        if vacuumAfter {
            try vacuum()
        }

        let sizeAfter = databaseSizeBytes()
        let reclaimed = max(0, sizeBefore - sizeAfter)

        return PruneResult(
            deletedActivityCount: deletedActivity,
            deletedEventsCount: deletedEvents,
            deletedLiveSessionsCount: deletedLive,
            bytesReclaimed: reclaimed
        )
    }

    /// Reclaims unused disk space by running SQLite VACUUM.
    func vacuum() throws {
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
    }

    /// Returns the physical database file size in bytes, or 0 if in-memory.
    func databaseSizeBytes() -> Int64 {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flightdeck", isDirectory: true)
            .appendingPathComponent("flightdeck.sqlite")
        let attrs = try? FileManager.default.attributesOfItem(atPath: support.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

