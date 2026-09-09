import Foundation

/// A single timestamped hardware telemetry sample in the timeline ring buffer.
public struct TelemetryPoint: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let cpu: Double
    public let gpu: Double
    public let memBytes: Int64
    public let netKB: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        cpu: Double,
        gpu: Double,
        memBytes: Int64,
        netKB: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memBytes = memBytes
        self.netKB = netKB
    }
}

/// A high-performance, ring-buffered timeline recording real-time system metrics
/// over a rolling 5-10 minute window with instant playhead scrubbing.
@Observable
public final class TimelineStore {
    public static let shared = TimelineStore()

    public private(set) var points: [TelemetryPoint] = []
    public var scrubFraction: CGFloat? = nil // nil = live edge, 0.0...1.0 = historical
    public let maxCount: Int

    public init(maxCount: Int = 300) {
        self.maxCount = maxCount
    }

    public func append(cpu: Double, gpu: Double, memBytes: Int64, netKB: Double) {
        let pt = TelemetryPoint(cpu: cpu, gpu: gpu, memBytes: memBytes, netKB: netKB)
        points.append(pt)
        if points.count > maxCount {
            points.removeFirst(points.count - maxCount)
        }
    }

    public var scrubbedPoint: TelemetryPoint? {
        guard !points.isEmpty else { return nil }
        guard let frac = scrubFraction else { return points.last }
        let clamped = min(1.0, max(0.0, frac))
        let index = Int(clamped * CGFloat(points.count - 1))
        return points[min(points.count - 1, max(0, index))]
    }
}
