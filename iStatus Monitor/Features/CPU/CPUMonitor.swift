import Darwin
import Foundation

actor CPUMonitor {
    struct TickSample: Sendable, Equatable {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    private var previousTicks: [TickSample]?
    private var historyStorage: [CPUSnapshot] = []

    var history: [CPUSnapshot] {
        historyStorage
    }

    func snapshots(every interval: Duration = .seconds(1)) -> AsyncStream<CPUSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let snapshot = sampleSnapshot() {
                        continuation.yield(snapshot)
                    }

                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func latestSnapshot() -> CPUSnapshot? {
        sampleSnapshot()
    }

    private func sampleSnapshot() -> CPUSnapshot? {
        guard let currentTicks = fetchTickSamples() else { return nil }

        let loadAverage = readLoadAverage()
        let now = Date()

        guard let previousTicks else {
            self.previousTicks = currentTicks
            let baseline = Self.makeBaselineSnapshot(timestamp: now, coreCount: currentTicks.count, loadAverage: loadAverage)
            appendToHistory(baseline)
            return baseline
        }

        let snapshot = Self.computeSnapshot(
            timestamp: now,
            previous: previousTicks,
            current: currentTicks,
            loadAverage: loadAverage
        )

        self.previousTicks = currentTicks
        appendToHistory(snapshot)
        return snapshot
    }

    private func appendToHistory(_ snapshot: CPUSnapshot) {
        historyStorage.append(snapshot)
        if historyStorage.count > 60 {
            historyStorage.removeFirst(historyStorage.count - 60)
        }
    }

    private func fetchTickSamples() -> [TickSample]? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return nil
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        var output: [TickSample] = []
        output.reserveCapacity(Int(cpuCount))

        for core in 0 ..< Int(cpuCount) {
            let base = core * stride
            // `integer_t` (Int32) tick counters increase monotonically and can
            // exceed Int32.max on long-uptime machines, arriving here as negative
            // values. `UInt32(bitPattern:)` reinterprets the bits without trapping
            // (a plain `UInt32(_:)` conversion would crash); the Int64 delta math
            // in computeSnapshot then handles the unsigned wrap-around.
            let user = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)])

            output.append(TickSample(user: user, system: system, idle: idle, nice: nice))
        }

        return output
    }

    private func readLoadAverage() -> LoadAverage {
        var values = [Double](repeating: 0, count: 3)
        let result = getloadavg(&values, Int32(values.count))
        guard result == 3 else {
            return LoadAverage(one: 0, five: 0, fifteen: 0)
        }
        return LoadAverage(one: values[0], five: values[1], fifteen: values[2])
    }

    static func makeBaselineSnapshot(
        timestamp: Date,
        coreCount: Int,
        loadAverage: LoadAverage
    ) -> CPUSnapshot {
        let cores = (0 ..< coreCount).map {
            CoreUsage(coreIndex: $0, user: 0, system: 0, idle: 1, nice: 0)
        }
        return CPUSnapshot(timestamp: timestamp, perCoreUsage: cores, overallLoad: 0, loadAverage: loadAverage)
    }

    static func computeSnapshot(
        timestamp: Date,
        previous: [TickSample],
        current: [TickSample],
        loadAverage: LoadAverage
    ) -> CPUSnapshot {
        let limit = min(previous.count, current.count)
        var perCore: [CoreUsage] = []
        perCore.reserveCapacity(limit)

        var totalActive: Float = 0
        var activeCores: Float = 0

        for idx in 0 ..< limit {
            let p = previous[idx]
            let c = current[idx]

            let userDelta = max(0, Int64(c.user) - Int64(p.user))
            let systemDelta = max(0, Int64(c.system) - Int64(p.system))
            let idleDelta = max(0, Int64(c.idle) - Int64(p.idle))
            let niceDelta = max(0, Int64(c.nice) - Int64(p.nice))

            let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
            guard totalDelta > 0 else {
                perCore.append(CoreUsage(coreIndex: idx, user: 0, system: 0, idle: 1, nice: 0))
                continue
            }

            let total = Float(totalDelta)
            let user = Float(userDelta) / total
            let system = Float(systemDelta) / total
            let idle = Float(idleDelta) / total
            let nice = Float(niceDelta) / total

            let coreUsage = CoreUsage(coreIndex: idx, user: user, system: system, idle: idle, nice: nice)
            perCore.append(coreUsage)
            totalActive += coreUsage.active
            activeCores += 1
        }

        let overall = activeCores > 0 ? totalActive / activeCores : 0
        return CPUSnapshot(timestamp: timestamp, perCoreUsage: perCore, overallLoad: overall, loadAverage: loadAverage)
    }
}
