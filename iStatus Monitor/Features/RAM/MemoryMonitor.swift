import Darwin
import Foundation
import MachO

actor MemoryMonitor {
    func snapshots(every interval: Duration = .seconds(2)) -> AsyncStream<MemorySnapshot> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let snapshot = latestSnapshot() {
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

    func latestSnapshot() -> MemorySnapshot? {
        guard let vmStats = readVMStatistics() else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory

        let wired = UInt64(vmStats.wire_count) * pageSize
        let active = UInt64(vmStats.active_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let inactive = UInt64(vmStats.inactive_count) * pageSize
        let free = UInt64(vmStats.free_count) * pageSize

        let used = wired + active + compressed
        let pressure = pressureLevel(used: used, total: total)

        let swap = readSwapInfo()

        return MemorySnapshot(
            timestamp: Date(),
            totalBytes: total,
            usedBytes: used,
            wiredBytes: wired,
            appBytes: active,
            compressedBytes: compressed,
            cachedBytes: inactive,
            freeBytes: free,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressure: pressure
        )
    }

    func read() async -> RAMMetrics {
        guard let snapshot = latestSnapshot() else {
            return RAMMetrics.empty
        }
        return RAMMetrics(usedBytes: snapshot.usedBytes, totalBytes: snapshot.totalBytes)
    }

    private func readVMStatistics() -> vm_statistics64_data_t? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        // Queries host-level virtual memory counters (active/inactive/wired/free/compressed pages).
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return stats
    }

    private func readSwapInfo() -> (used: UInt64, total: UInt64) {
        var fs = statfs()

        // Reads filesystem capacity statistics for /private/var/vm where macOS stores swap files.
        let status = "/private/var/vm".withCString { ptr in
            statfs(ptr, &fs)
        }

        guard status == 0 else { return (0, 0) }

        let blockSize = UInt64(fs.f_bsize)
        let total = UInt64(fs.f_blocks) * blockSize
        let available = UInt64(fs.f_bavail) * blockSize
        let used = total > available ? total - available : 0

        return (used, total)
    }

    private func pressureLevel(used: UInt64, total: UInt64) -> MemoryPressureLevel {
        guard total > 0 else { return .normal }
        let ratio = Double(used) / Double(total)

        if ratio >= 0.90 { return .critical }
        if ratio >= 0.75 { return .warning }
        return .normal
    }
}
