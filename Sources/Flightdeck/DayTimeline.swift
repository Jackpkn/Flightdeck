import Foundation

/// One stretch of app usage as drawn on the timeline.
struct AppSegment: Identifiable, Sendable {
    let id: String
    let appName: String
    let bundleId: String
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

/// One labeled track on the timeline: an app and every segment it occupied.
struct TimelineTrack: Identifiable {
    var id: String { name }
    let name: String
    let total: TimeInterval
    let segments: [AppSegment]
    /// True for the rolled-up remainder track rather than a real app.
    let isOther: Bool
}

/// Loads one day of app segments and steps between days — the first thing that
/// actually reads back the accumulated SQLite history instead of only today.
@Observable
final class DayTimeline {
    private(set) var day: Date = Calendar.current.startOfDay(for: Date())
    private(set) var segments: [AppSegment] = []

    var isToday: Bool { Calendar.current.isDateInToday(day) }

    func load() {
        segments = ActivityDatabase.shared?.segments(on: day) ?? []
    }

    func step(_ days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        // Never walk into the future; there's nothing recorded there.
        if next > Calendar.current.startOfDay(for: Date()) { return }
        day = next
        load()
    }

    func goToToday() {
        day = Calendar.current.startOfDay(for: Date())
        load()
    }

    /// Groups into per-app tracks, biggest first, with everything past `limit`
    /// rolled into a single "Other" track rather than dozens of 3px slivers.
    func tracks(limit: Int, extra: AppSegment?) -> [TimelineTrack] {
        var all = segments
        if let extra { all.append(extra) }

        var byApp: [String: [AppSegment]] = [:]
        for segment in all {
            byApp[segment.appName, default: []].append(segment)
        }

        let ranked = byApp
            .map { (name: $0.key, segments: $0.value, total: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.total > $1.total }

        var tracks = ranked.prefix(limit).map {
            TimelineTrack(name: $0.name, total: $0.total, segments: $0.segments, isOther: false)
        }

        let rest = ranked.dropFirst(limit)
        if !rest.isEmpty {
            let segments = rest.flatMap(\.segments)
            tracks.append(
                TimelineTrack(
                    name: "Other (\(rest.count))",
                    total: rest.reduce(0) { $0 + $1.total },
                    segments: segments,
                    isOther: true
                )
            )
        }
        return tracks
    }

    /// The drawn window, snapped to whole hours around the real activity — a
    /// fixed midnight-to-midnight axis would be mostly empty space.
    func window(extra: AppSegment?) -> (start: Date, end: Date)? {
        var all = segments
        if let extra { all.append(extra) }
        guard let first = all.map(\.startedAt).min(),
              let last = all.map(\.endedAt).max() else { return nil }

        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .hour, for: first)?.start ?? first
        let endBase = isToday ? max(last, Date()) : last
        let end = calendar.dateInterval(of: .hour, for: endBase)?.end ?? endBase
        return (start, end)
    }
}
