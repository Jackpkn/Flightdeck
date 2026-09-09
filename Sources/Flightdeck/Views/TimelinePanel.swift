import SwiftUI

/// The day as a Gantt track per app. Segments are deliberately a single color:
/// each track is labeled, so identity is already carried by the row, and
/// recycling three hues across ten apps would make different apps look related.
struct TimelinePanel: View {
    @Environment(DayTimeline.self) private var timeline
    @Environment(ActivityWatcher.self) private var watcher

    private static let trackLimit = 9

    private var live: AppSegment? {
        timeline.isToday ? watcher.liveSegment : nil
    }

    private var tracks: [TimelineTrack] {
        timeline.tracks(limit: Self.trackLimit, extra: live)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let window = timeline.window(extra: live), !tracks.isEmpty {
                VStack(spacing: 8) {
                    HourAxis(start: window.start, end: window.end)
                    ForEach(tracks) { track in
                        TrackRow(track: track, window: window, isToday: timeline.isToday)
                    }
                }
            } else {
                Text(timeline.isToday
                     ? "No activity recorded yet today — switch between apps and this fills in."
                     : "Nothing recorded on this day.")
                    .font(Theme.ui(12.5)).foregroundStyle(Theme.ink3)
                    .padding(.vertical, 8)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(accent: Theme.copilotColor)
        .cornerBracket(color: Theme.copilotColor)
        .onAppear { timeline.load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            LiveDot(color: timeline.isToday ? Theme.copilotColor : Theme.ink3)
            Text("DAY TIMELINE").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)

            Spacer(minLength: 8)

            Text(Self.total(tracks))
                .font(Theme.mono(12, weight: .semibold)).foregroundStyle(Theme.ink1)

            HStack(spacing: 4) {
                Button { timeline.step(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.ink3)
                .help("Previous day")

                Button { timeline.goToToday() } label: {
                    Text(timeline.day.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(timeline.isToday ? Theme.copilotColor : Theme.ink2)
                        .frame(width: 84)
                }
                .buttonStyle(.plain)
                .help("Jump to today")

                Button { timeline.step(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(timeline.isToday ? Theme.ink3.opacity(0.35) : Theme.ink3)
                .disabled(timeline.isToday)
                .help("Next day")
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Theme.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private static func total(_ tracks: [TimelineTrack]) -> String {
        let seconds = tracks.reduce(0) { $0 + $1.total }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// Hour ticks and labels across the drawn window, aligned to the track area.
private struct HourAxis: View {
    let start: Date
    let end: Date

    private var hours: [Date] {
        var result: [Date] = []
        var cursor = start
        while cursor <= end {
            result.append(cursor)
            guard let next = Calendar.current.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    var body: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: TrackRow.labelWidth)
            GeometryReader { geo in
                let span = end.timeIntervalSince(start)
                ZStack(alignment: .topLeading) {
                    ForEach(hours, id: \.self) { hour in
                        let x = span > 0 ? geo.size.width * hour.timeIntervalSince(start) / span : 0
                        Text(hour.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                            .font(Theme.mono(8.5))
                            .foregroundStyle(Theme.ink3.opacity(0.75))
                            .offset(x: max(0, min(x - 8, geo.size.width - 16)))
                    }
                }
            }
            .frame(height: 11)
            Spacer().frame(width: TrackRow.totalWidth)
        }
    }
}

private struct TrackRow: View {
    let track: TimelineTrack
    let window: (start: Date, end: Date)
    let isToday: Bool

    static let labelWidth: CGFloat = 116
    static let totalWidth: CGFloat = 54

    private var barColor: Color {
        track.isOther ? Theme.ink3.opacity(0.55) : Theme.copilotColor.opacity(0.8)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(track.name)
                .font(Theme.ui(11.5))
                .foregroundStyle(track.isOther ? Theme.ink3 : Theme.ink2)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)

            GeometryReader { geo in
                let span = window.end.timeIntervalSince(window.start)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.track.opacity(0.65))

                    // Hour gridlines, so a block's position reads as a time.
                    ForEach(Array(hourOffsets(span: span, width: geo.size.width).enumerated()), id: \.offset) { _, x in
                        Rectangle()
                            .fill(Theme.hairline2)
                            .frame(width: 1)
                            .offset(x: x)
                    }

                    ForEach(track.segments) { segment in
                        let x = span > 0 ? geo.size.width * segment.startedAt.timeIntervalSince(window.start) / span : 0
                        let w = span > 0 ? geo.size.width * segment.duration / span : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segment.id == "live" ? Theme.copilotColor : barColor)
                            .frame(width: max(1.5, w))
                            .offset(x: max(0, x))
                            .help("\(segment.appName) · \(Self.range(segment)) · \(Self.duration(segment.duration))")
                    }
                }
            }
            .frame(height: 16)

            Text(Self.duration(track.total))
                .font(Theme.mono(10.5)).foregroundStyle(Theme.ink1)
                .frame(width: Self.totalWidth, alignment: .trailing)
        }
    }

    private func hourOffsets(span: TimeInterval, width: CGFloat) -> [CGFloat] {
        guard span > 0 else { return [] }
        var offsets: [CGFloat] = []
        var cursor = window.start
        while cursor <= window.end {
            offsets.append(width * cursor.timeIntervalSince(window.start) / span)
            guard let next = Calendar.current.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return offsets
    }

    private static func range(_ segment: AppSegment) -> String {
        let start = segment.startedAt.formatted(date: .omitted, time: .shortened)
        let end = segment.endedAt.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return "\(h)h \(m)m" }
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
