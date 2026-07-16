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

    // MARK: - Baseline

    @Test("makeBaselineSnapshot produces all-idle cores and zero overall load")
    func makeBaselineSnapshotAllIdle() {
        let snapshot = CPUMonitor.makeBaselineSnapshot(
            timestamp: Date(timeIntervalSince1970: 1000),
            coreCount: 4,
            loadAverage: LoadAverage(one: 0, five: 0, fifteen: 0)
        )

        #expect(snapshot.perCoreUsage.count == 4)
        #expect(snapshot.overallLoad == 0)
        for core in snapshot.perCoreUsage {
            #expect(core.user == 0)
            #expect(core.system == 0)
            #expect(core.idle == 1)
            #expect(core.nice == 0)
            #expect(core.active == 0)
        }
    }

    @Test("makeBaselineSnapshot handles a zero-core machine")
    func makeBaselineSnapshotZeroCores() {
        let snapshot = CPUMonitor.makeBaselineSnapshot(
            timestamp: Date(),
            coreCount: 0,
            loadAverage: LoadAverage(one: 1, five: 2, fifteen: 3)
        )

        #expect(snapshot.perCoreUsage.isEmpty)
        #expect(snapshot.overallLoad == 0)
        // Load average is passed through untouched.
        #expect(snapshot.loadAverage == LoadAverage(one: 1, five: 2, fifteen: 3))
    }

    // MARK: - Zero / idle / saturated deltas

    @Test("computeSnapshot treats a zero delta as fully idle, not NaN")
    func computeSnapshotZeroDeltaIsIdle() {
        let ticks = [CPUMonitor.TickSample(user: 10, system: 5, idle: 3, nice: 2)]
        let snapshot = CPUMonitor.computeSnapshot(
            timestamp: Date(),
            previous: ticks,
            current: ticks, // identical -> every delta is 0
            loadAverage: LoadAverage(one: 0, five: 0, fifteen: 0)
        )

        #expect(snapshot.perCoreUsage.count == 1)
        let core = snapshot.perCoreUsage[0]
        #expect(core.user == 0 && core.system == 0 && core.idle == 1 && core.nice == 0)
        #expect(snapshot.overallLoad == 0)
    }

    @Test("computeSnapshot reports 100% idle when only the idle counter advanced")
    func computeSnapshotIdleFullySaturated() {
        let previous = [CPUMonitor.TickSample(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [CPUMonitor.TickSample(user: 0, system: 0, idle: 1000, nice: 0)]
        let snapshot = CPUMonitor.computeSnapshot(
            timestamp: Date(),
            previous: previous,
            current: current,
            loadAverage: LoadAverage(one: 0, five: 0, fifteen: 0)
        )

        let core = snapshot.perCoreUsage[0]
        #expect(abs(core.idle - 1.0) < 0.0001)
        #expect(core.user == 0 && core.system == 0 && core.nice == 0)
        // `active` excludes idle, so a fully-idle core reads as 0% active / 0% load.
        #expect(core.active == 0)
        #expect(snapshot.overallLoad == 0)
    }

    @Test("computeSnapshot reports 100% active when idle counter did not advance")
    func computeSnapshotFullyUtilized() {
        let previous = [CPUMonitor.TickSample(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [CPUMonitor.TickSample(user: 500, system: 300, idle: 0, nice: 200)]
        let snapshot = CPUMonitor.computeSnapshot(
            timestamp: Date(),
            previous: previous,
            current: current,
            loadAverage: LoadAverage(one: 0, five: 0, fifteen: 0)
        )

        let core = snapshot.perCoreUsage[0]
        #expect(abs(core.user - 0.5) < 0.0001)
        #expect(abs(core.system - 0.3) < 0.0001)
        #expect(core.idle == 0)
        #expect(abs(core.nice - 0.2) < 0.0001)
        #expect(abs(core.active - 1.0) < 0.0001)
        #expect(abs(snapshot.overallLoad - 1.0) < 0.0001)
    }

    @Test("computeSnapshot overall load is the mean of per-core active load")
    func computeSnapshotOverallIsMeanOfActive() {
        // core0: fully active, core1: half active, core2: idle (advances only idle)
        let previous = [
            CPUMonitor.TickSample(user: 0, system: 0, idle: 0, nice: 0),
            CPUMonitor.TickSample(user: 0, system: 0, idle: 0, nice: 0),
            CPUMonitor.TickSample(user: 0, system: 0, idle: 0, nice: 0)
        ]
        let current = [
            CPUMonitor.TickSample(user: 100, system: 0, idle: 0, nice: 0), // active 1.0
            CPUMonitor.TickSample(user: 50, system: 0, idle: 50, nice: 0), // active 0.5
            CPUMonitor.TickSample(user: 0, system: 0, idle: 100, nice: 0) // active 0.0
        ]
        let snapshot = CPUMonitor.computeSnapshot(
            timestamp: Date(),
            previous: previous,
            current: current,
            loadAverage: LoadAverage(one: 0, five: 0, fifteen: 0)
        )

        #expect(snapshot.perCoreUsage.count == 3)
        #expect(abs(snapshot.perCoreUsage[0].active - 1.0) < 0.0001)
        #expect(abs(snapshot.perCoreUsage[1].active - 0.5) < 0.0001)
        #expect(snapshot.perCoreUsage[2].active == 0)
        // (1.0 + 0.5 + 0.0) / 3 == 0.5
        #expect(abs(snapshot.overallLoad - 0.5) < 0.0001)
    }

    // MARK: - Malformed / overflow inputs

    @Test("computeSnapshot tolerates mismatched core counts by using the shorter")
    func computeSnapshotMismatchedCoreCounts() {
        let previous = [
            CPUMonitor.TickSample(user: 0, system: 0, idle: 0, nice: 0),
            CPUMonitor.TickSample(user: 0, system: 0, idle: 0, nice: 0)
        ]
        let current = [
            CPUMonitor.TickSample(user: 100, system: 0, idle: 0, nice: 0) // only one core
        ]
        let snapshot = CPUMonitor.computeSnapshot(
            timestamp: Date(),
            previous: previous,
            current: current,
            loadAverage: LoadAverage(one: 0, five: 0, fifteen: 0)
        )

        #expect(snapshot.perCoreUsage.count == 1)
        #expect(abs(snapshot.perCoreUsage[0].user - 1.0) < 0.0001)
        #expect(abs(snapshot.overallLoad - 1.0) < 0.0001)
    }

    @Test("computeSnapshot handles empty tick arrays without crashing")
    func computeSnapshotEmptyArrays() {
        let snapshot = CPUMonitor.computeSnapshot(
            timestamp: Date(),
            previous: [],
            current: [],
            loadAverage: LoadAverage(one: 0, five: 0, fifteen: 0)
        )

        #expect(snapshot.perCoreUsage.isEmpty)
        #expect(snapshot.overallLoad == 0)
    }

    @Test("computeSnapshot is robust to UInt32 tick-counter wrap-around")
    func computeSnapshotUInt32WrapAround() {
        // The raw tick counters are stored as UInt32 bits. After ~497 days of
        // uptime a counter wraps past UInt32.max (4_294_967_295) back to a small
        // value, so `current < previous`. The implementation clamps the negative
        // delta to 0 via `max(0, …)`, so the wrapped counter's contribution is
        // dropped for this single tick (graceful) rather than producing a negative
        // or NaN fraction. The other (non-wrapped) counters remain valid.
        let previous = [CPUMonitor.TickSample(
            user: 4_294_967_290, // just below UInt32.max
            system: 100,
            idle: 200,
            nice: 10
        )]
        let current = [CPUMonitor.TickSample(
            user: 5, // wrapped
            system: 150,
            idle: 250,
            nice: 20
        )]

        let snapshot = CPUMonitor.computeSnapshot(
            timestamp: Date(),
            previous: previous,
            current: current,
            loadAverage: LoadAverage(one: 0, five: 0, fifteen: 0)
        )

        #expect(snapshot.perCoreUsage.count == 1)
        let core = snapshot.perCoreUsage[0]
        // No NaN / Infinity anywhere, despite the overflow on `user`.
        #expect(!core.user.isNaN && !core.user.isInfinite)
        #expect(!core.system.isNaN && !core.idle.isNaN && !core.nice.isNaN)
        // Fractions remain valid and still sum to 1.
        #expect(abs((core.user + core.system + core.idle + core.nice) - 1.0) < 0.0001)
        // The wrapped `user` counter is dropped: its share is 0 this tick.
        #expect(core.user == 0)
        #expect(abs(core.system - (50.0 / 110.0)) < 0.001)
        #expect(abs(core.idle - (50.0 / 110.0)) < 0.001)
        #expect(abs(core.nice - (10.0 / 110.0)) < 0.001)
    }
}
