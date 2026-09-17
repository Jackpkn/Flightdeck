import Foundation
import Testing
import GRDB
@testable import Flightdeck

@Suite("Activity Database Prune & Secret Scrubbing")
struct ActivityDatabasePruneTests {

    @Test("Prunes records older than specified cutoff days")
    func prunesOldRecords() throws {
        let db = try ActivityDatabase.inMemory()

        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -25, to: now)!
        let recentDate = Calendar.current.date(byAdding: .day, value: -2, to: now)!

        // Insert old and recent app activity
        db.save(appName: "OldApp", bundleId: "com.old.app", windowTitle: "Old", startedAt: oldDate, endedAt: oldDate.addingTimeInterval(300))
        db.save(appName: "RecentApp", bundleId: "com.recent.app", windowTitle: "Recent", startedAt: recentDate, endedAt: recentDate.addingTimeInterval(300))

        // Insert old and recent AI events
        db.insertEvent(AIEventRecord(id: nil, sessionId: "old-session", event: "tool_use", toolName: "Bash", detail: "npm test", timestamp: oldDate))
        db.insertEvent(AIEventRecord(id: nil, sessionId: "recent-session", event: "tool_use", toolName: "Bash", detail: "git status", timestamp: recentDate))

        // Insert old and recent live sessions
        db.upsertSession(SessionLiveRecord(sessionId: "old-live", project: "P1", branch: "main", model: "sonnet", contextTokens: 1000, totalCostUsd: 1.0, lastFile: "a.txt", updatedAt: oldDate))
        db.upsertSession(SessionLiveRecord(sessionId: "recent-live", project: "P2", branch: "main", model: "sonnet", contextTokens: 1000, totalCostUsd: 1.0, lastFile: "b.txt", updatedAt: recentDate))

        // Prune older than 14 days
        let result = try db.prune(olderThanDays: 14, vacuumAfter: false)

        #expect(result.deletedActivityCount == 1)
        #expect(result.deletedEventsCount == 1)
        #expect(result.deletedLiveSessionsCount == 1)
        #expect(result.totalDeletedRows == 3)

        // Verify remaining recent records
        let liveRemaining = db.fetchLiveSessions()
        #expect(liveRemaining.count == 1)
        #expect(liveRemaining.first?.sessionId == "recent-live")

        let eventsRemaining = db.recentEvents(limit: 10)
        #expect(eventsRemaining.count == 1)
        #expect(eventsRemaining.first?.sessionId == "recent-session")
    }

    @Test("Automatically scrubs secrets before writing events to SQLite")
    func scrubsSecretsOnEventInsert() throws {
        let db = try ActivityDatabase.inMemory()
        let secretKey = "sk-ant-api03-1234567890abcdef1234567890abcdef1234567890abcdef1234567890"

        let event = AIEventRecord(
            id: nil,
            sessionId: "test-sec",
            event: "bash",
            toolName: "Bash",
            detail: "export ANTHROPIC_API_KEY=\(secretKey)",
            timestamp: Date()
        )
        db.insertEvent(event)

        let saved = db.recentEvents(limit: 5).first
        #expect(saved != nil)
        #expect(saved?.detail?.contains(secretKey) == false)
        #expect(saved?.detail?.contains("sk-ant-api03-••••••••") == true)
    }
}
