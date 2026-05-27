import Foundation
import Testing
@testable import iStatus_Monitor

struct CPUMonitorTests {
    @Test("computeSnapshot calculates per-core and overall CPU load from tick deltas")
    func computeSnapshotFromMockTicks() {
        let previous = [
            CPUMonitor.TickSample(user: 100, system: 50, idle: 200, nice: 10),
            CPUMonitor.TickSample(user: 120, system: 40, idle: 240, nice: 0)
        ]

        let current = [
            CPUMonitor.TickSample(user: 140, system: 70, idle: 230, nice: 20),
            CPUMonitor.TickSample(user: 180, system: 60, idle: 300, nice: 10)
        ]

        let snapshot = CPUMonitor.computeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1000),
            previous: previous,
            current: current,
            loadAverage: LoadAverage(one: 1.25, five: 1.10, fifteen: 0.95)
        )

        #expect(snapshot.perCoreUsage.count == 2)

        let core0 = snapshot.perCoreUsage[0]
        #expect(abs(core0.user - 0.40) < 0.001)
        #expect(abs(core0.system - 0.20) < 0.001)
        #expect(abs(core0.idle - 0.30) < 0.001)
        #expect(abs(core0.nice - 0.10) < 0.001)

        let core1 = snapshot.perCoreUsage[1]
        #expect(abs(core1.user - 0.40) < 0.001)
        #expect(abs(core1.system - 0.1333) < 0.001)
        #expect(abs(core1.idle - 0.40) < 0.001)
        #expect(abs(core1.nice - 0.0667) < 0.001)

        #expect(abs(snapshot.overallLoad - 0.65) < 0.001)
        #expect(snapshot.loadAverage.one == 1.25)
        #expect(snapshot.loadAverage.five == 1.10)
        #expect(snapshot.loadAverage.fifteen == 0.95)
    }
}
