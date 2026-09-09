import Testing
import Foundation
@testable import Flightdeck

@Suite("TimelineStoreTests")
struct TimelineStoreTests {
    @Test("Ring buffer caps items and maintains rolling window")
    func ringBufferCap() {
        let store = TimelineStore(maxCount: 5)
        #expect(store.points.isEmpty)
        #expect(store.scrubbedPoint == nil)

        for i in 1...10 {
            store.append(cpu: Double(i * 10), gpu: Double(i * 5), memBytes: Int64(i * 1024), netKB: Double(i * 2))
        }

        #expect(store.points.count == 5)
        // Oldest should be 60.0 CPU, newest 100.0 CPU
        #expect(store.points.first?.cpu == 60.0)
        #expect(store.points.last?.cpu == 100.0)
    }

    @Test("Scrub fraction accurately computes historical playhead points")
    func scrubFractionMath() {
        let store = TimelineStore(maxCount: 10)
        for i in 0..<5 {
            store.append(cpu: Double(i), gpu: 0, memBytes: 0, netKB: 0)
        }

        // Live edge (nil)
        store.scrubFraction = nil
        #expect(store.scrubbedPoint?.cpu == 4.0)

        // Historical scrubbing
        store.scrubFraction = 0.0
        #expect(store.scrubbedPoint?.cpu == 0.0)

        store.scrubFraction = 0.5
        #expect(store.scrubbedPoint?.cpu == 2.0)

        store.scrubFraction = 1.0
        #expect(store.scrubbedPoint?.cpu == 4.0)

        // Clamping bounds
        store.scrubFraction = -0.5
        #expect(store.scrubbedPoint?.cpu == 0.0)

        store.scrubFraction = 2.0
        #expect(store.scrubbedPoint?.cpu == 4.0)
    }
}
