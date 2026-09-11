import Testing
import Foundation
@testable import Flightdeck

@Suite("Claude usage limits")
struct ClaudeUsageLimitsTests {

    /// Shaped exactly like the `cachedUsageUtilization` block Claude Code writes to
    /// ~/.claude.json, including the codename windows and nulls it really contains.
    private func payload(
        fetchedAtMs: Double = 1_788_625_880_171,
        sessionPercent: Int = 18,
        sessionResets: String = "2026-09-05T21:00:00.061013+00:00",
        weeklyPercent: Int = 3,
        weeklyResets: String = "2026-09-11T15:00:00.061037+00:00"
    ) -> Data {
        let json = """
        {
          "cachedUsageUtilization": {
            "fetchedAtMs": \(fetchedAtMs),
            "accountUuid": "7bf7652a-8e6a-46c9-a596-02c1a67a0db0",
            "utilization": {
              "five_hour": { "utilization": \(sessionPercent), "resets_at": "\(sessionResets)" },
              "seven_day": { "utilization": \(weeklyPercent), "resets_at": "\(weeklyResets)" },
              "seven_day_opus": null,
              "nimbus_quill": { "utilization": 0, "resets_at": null },
              "extra_usage": { "is_enabled": false, "user_disabled": true },
              "limits": [
                {
                  "kind": "session", "group": "session", "percent": \(sessionPercent),
                  "severity": "normal", "resets_at": "\(sessionResets)",
                  "scope": null, "is_active": true
                },
                {
                  "kind": "weekly_all", "group": "weekly", "percent": \(weeklyPercent),
                  "severity": "normal", "resets_at": "\(weeklyResets)",
                  "scope": null, "is_active": false
                }
              ]
            }
          }
        }
        """
        return Data(json.utf8)
    }

    private var fetchedAt: Date { Date(timeIntervalSince1970: 1_788_625_880.171) }

    @Test("Parses the real limits array Claude Code writes")
    func parsesLimits() throws {
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(payload()))
        #expect(snapshot.limits.count == 2)

        let session = try #require(snapshot.limits.first { $0.kind == "session" })
        #expect(session.percent == 18)
        #expect(session.isActive)
        #expect(session.resetsAt != nil)

        let weekly = try #require(snapshot.limits.first { $0.kind == "weekly_all" })
        #expect(weekly.percent == 3)
        #expect(!weekly.isActive)
    }

    @Test("Internal codename windows are not surfaced as limits")
    func skipsCodenameWindows() throws {
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(payload()))
        #expect(!snapshot.limits.contains { $0.kind.contains("nimbus") })
    }

    @Test("Limit kinds get readable labels")
    func readableLabels() throws {
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(payload()))
        let session = try #require(snapshot.limits.first { $0.kind == "session" })
        #expect(session.label == "5-HOUR SESSION")
        let weekly = try #require(snapshot.limits.first { $0.kind == "weekly_all" })
        #expect(weekly.label == "WEEKLY · ALL MODELS")
    }

    @Test("An unknown future limit kind is humanised, not dropped")
    func unknownKindIsHumanised() {
        let limit = ClaudeUsageLimit(
            kind: "monthly_fable", group: "monthly", percent: 5,
            severity: .normal, resetsAt: nil, isActive: true
        )
        #expect(limit.label == "MONTHLY FABLE")
    }

    @Test("The snapshot records when Claude Code fetched it")
    func recordsFetchTime() throws {
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(payload()))
        #expect(abs(snapshot.fetchedAt.timeIntervalSince(fetchedAt)) < 0.01)
    }

    @Test("A cache older than the freshness window is reported as stale")
    func detectsStaleCache() throws {
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(payload()))
        // Five and a half days after the fetch — exactly the gap seen on disk.
        let now = fetchedAt.addingTimeInterval(5.5 * 86_400)
        #expect(snapshot.isStale(now: now))
        #expect(snapshot.age(now: now) > 5 * 86_400)
    }

    @Test("A cache fetched moments ago is fresh")
    func detectsFreshCache() throws {
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(payload()))
        #expect(!snapshot.isStale(now: fetchedAt.addingTimeInterval(30)))
    }

    @Test("A window whose reset time has passed is expired, not still-consumed")
    func expiredWindow() throws {
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(payload()))
        let session = try #require(snapshot.limits.first { $0.kind == "session" })
        // resets_at is 2026-09-05T21:00Z; this is days later.
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        #expect(session.isExpired(now: now))
        #expect(session.timeUntilReset(now: now) == nil)
    }

    @Test("A live window reports the time left before it resets")
    func timeUntilReset() throws {
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(payload()))
        let weekly = try #require(snapshot.limits.first { $0.kind == "weekly_all" })
        let resetsAt = try #require(weekly.resetsAt)
        let now = resetsAt.addingTimeInterval(-3600)
        #expect(!weekly.isExpired(now: now))
        let remaining = try #require(weekly.timeUntilReset(now: now))
        #expect(abs(remaining - 3600) < 1)
    }

    @Test("Severity escalates with utilization when the payload says normal")
    func severityFromPercent() {
        #expect(ClaudeUsageLimit.Severity.forPercent(10) == .normal)
        #expect(ClaudeUsageLimit.Severity.forPercent(80) == .warning)
        #expect(ClaudeUsageLimit.Severity.forPercent(95) == .critical)
    }

    @Test("The most-consumed live window is the one worth surfacing")
    func headlineLimit() throws {
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(
            payload(sessionPercent: 12, weeklyPercent: 67)
        ))
        let now = Date(timeIntervalSince1970: 1_788_625_900)
        #expect(snapshot.headline(now: now)?.kind == "weekly_all")
    }

    @Test("Expired windows never become the headline")
    func headlineSkipsExpired() throws {
        // Session window sits at 90% but reset long ago; weekly at 3% is still live.
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(
            payload(sessionPercent: 90, sessionResets: "2026-09-05T21:00:00.061013+00:00")
        ))
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        #expect(snapshot.headline(now: now)?.kind != "session")
    }

    @Test("Falls back to the legacy utilization map when no limits array exists")
    func legacyFallback() throws {
        let legacy = Data("""
        {
          "cachedUsageUtilization": {
            "fetchedAtMs": 1788625880171,
            "utilization": {
              "five_hour": { "utilization": 42, "resets_at": "2026-09-11T21:00:00Z" },
              "seven_day": { "utilization": 7, "resets_at": "2026-09-14T15:00:00Z" }
            }
          }
        }
        """.utf8)
        let snapshot = try #require(ClaudeUsageLimitsReader.parse(legacy))
        #expect(snapshot.limits.count == 2)
        #expect(snapshot.limits.first { $0.kind == "session" }?.percent == 42)
    }

    @Test("Missing or malformed usage data yields no snapshot rather than zeros")
    func missingDataIsNil() {
        #expect(ClaudeUsageLimitsReader.parse(Data("{}".utf8)) == nil)
        #expect(ClaudeUsageLimitsReader.parse(Data("not json".utf8)) == nil)
        #expect(ClaudeUsageLimitsReader.parse(Data(#"{"cachedUsageUtilization": null}"#.utf8)) == nil)
    }

    @Test("Reads the real file on this machine without crashing")
    func readsRealFileSafely() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Only asserts it never traps — content varies by machine and account.
        _ = ClaudeUsageLimitsReader.load(from: url)
    }
}
