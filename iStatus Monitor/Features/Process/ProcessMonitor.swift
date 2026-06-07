import Darwin
import Foundation

// MARK: - Process Monitor
//
// Top CPU- and memory-consuming processes via `libproc`. Like the other monitors
// it is a pure-on-demand `actor` with no loop of its own — `SystemMonitorService`
// calls `latestSnapshot()` once per existing 1 s tick. Per-process CPU% is a
// delta of cumulative CPU time between ticks (same technique as `CPUMonitor`),
// so the first sample reports 0% and values populate from the second tick on.
//
// Requires the app to run **unsandboxed**: `proc_listpids` / `proc_pidinfo`
// return EPERM under the App Sandbox (verified empirically).
actor ProcessMonitor {
    private let topCount = 5

    /// pid → cumulative CPU time (ns) at the previous tick.
    private var previousCPUTime: [pid_t: UInt64] = [:]
    private var previousSampleTime: Date?

    func latestSnapshot(now: Date = Date()) -> ProcessSnapshot {
        let pids = listPIDs()
        guard !pids.isEmpty else { return ProcessSnapshot(timestamp: now, topByCPU: [], topByMemory: []) }

        let elapsed = previousSampleTime.map { now.timeIntervalSince($0) } ?? 0
        var currentCPUTime: [pid_t: UInt64] = [:]
        currentCPUTime.reserveCapacity(pids.count)

        var usages: [ProcessUsage] = []
        usages.reserveCapacity(pids.count)

        for pid in pids {
            guard let info = taskInfo(for: pid) else { continue }
            let totalCPUNanos = info.pti_total_user &+ info.pti_total_system
            currentCPUTime[pid] = totalCPUNanos

            var cpuPercent = 0.0
            if elapsed > 0, let previous = previousCPUTime[pid], totalCPUNanos >= previous {
                let deltaSeconds = Double(totalCPUNanos - previous) / 1_000_000_000.0
                cpuPercent = (deltaSeconds / elapsed) * 100.0
            }

            usages.append(
                ProcessUsage(
                    pid: pid,
                    name: name(for: pid),
                    cpuPercent: cpuPercent,
                    memoryBytes: info.pti_resident_size
                )
            )
        }

        previousCPUTime = currentCPUTime
        previousSampleTime = now

        let topByCPU = Array(usages.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(topCount))
        let topByMemory = Array(usages.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(topCount))
        return ProcessSnapshot(timestamp: now, topByCPU: topByCPU, topByMemory: topByMemory)
    }

    // MARK: libproc

    private func listPIDs() -> [pid_t] {
        let sizeProbe = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard sizeProbe > 0 else { return [] }

        let capacity = Int(sizeProbe) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, sizeProbe)
        guard written > 0 else { return [] }

        let count = Int(written) / MemoryLayout<pid_t>.stride
        return pids.prefix(count).filter { $0 > 0 }
    }

    private func taskInfo(for pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        return result == size ? info : nil
    }

    private func name(for pid: pid_t) -> String {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            let path = String(cString: pathBuffer)
            let last = (path as NSString).lastPathComponent
            if !last.isEmpty { return last }
        }
        // Fallback: the short accounting name (truncated to ~16 chars by the kernel).
        var nameBuffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
            return String(cString: nameBuffer)
        }
        return "pid \(pid)"
    }
}
