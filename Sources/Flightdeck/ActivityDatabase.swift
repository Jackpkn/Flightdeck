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

    private init() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flightdeck", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        dbQueue = try DatabaseQueue(path: support.appendingPathComponent("flightdeck.sqlite").path)
        try Self.migrator.migrate(dbQueue)
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
}
