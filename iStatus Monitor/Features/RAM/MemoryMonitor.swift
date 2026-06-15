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

        // `vm_kernel_page_size` is a global mutable `var` (not concurrency-safe
        // under Swift 6). `sysconf(_SC_PAGESIZE)` is a function call returning the
        // same VM page size (16 KB on Apple Silicon) without touching shared state.
        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let total = ProcessInfo.processInfo.physicalMemory

        // Categories follow Activity Monitor: app memory is anonymous (internal,
        // non-purgeable) pages; cached files are file-backed (external) plus
        // purgeable pages. active/inactive are page-aging states, not categories.
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let purgeable = UInt64(vmStats.purgeable_count) * pageSize
        let external = UInt64(vmStats.external_page_count) * pageSize
        let internalPages = UInt64(vmStats.internal_page_count) * pageSize
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        let cached = external + purgeable

        // Used = App Memory + Wired + Compressed (matches Activity Monitor's
        // "Memory Used"). Cached files are available and excluded from used.
        let used = app + wired + compressed
        // Free is genuinely unallocated memory, so the composition segments
        // (app + wired + compressed + cached + free) sum to physical total.
        let accounted = used + cached
        let free = total > accounted ? total - accounted : 0
        let pressure = pressureLevel(used: used, total: total)

        let swap = readSwapInfo()

        return MemorySnapshot(
            timestamp: Date(),
            totalBytes: total,
            usedBytes: used,
            wiredBytes: wired,
            appBytes: app,
            compressedBytes: compressed,
            cachedBytes: cached,
            freeBytes: free,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressure: pressure
        )
    }

    func read() async -> MemoryMetrics {
        guard let snapshot = latestSnapshot() else {
            return MemoryMetrics.empty
        }
        return MemoryMetrics(usedBytes: snapshot.usedBytes, totalBytes: snapshot.totalBytes)
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
        // Reads the kernel's swap accounting (vm.swapusage), matching Activity Monitor
        // and `sysctl vm.swapusage`. xsw_usage fields are already in bytes.
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride

        let status = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard status == 0 else { return (0, 0) }

        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }

    private func pressureLevel(used: UInt64, total: UInt64) -> MemoryPressureLevel {
        guard total > 0 else { return .normal }
        let ratio = Double(used) / Double(total)

        if ratio >= 0.90 { return .critical }
        if ratio >= 0.75 { return .warning }
        return .normal
    }
}
