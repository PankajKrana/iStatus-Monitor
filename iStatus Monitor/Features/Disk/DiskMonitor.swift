import Foundation
import IOKit

/// Collects disk capacity (per mounted volume) and real read/write throughput.
///
/// Capacity comes from `FileManager` volume resource values. Throughput is derived
/// from the cumulative byte counters published by every `IOBlockStorageDriver` in the
/// IORegistry, sampled as a delta between ticks (mirrors `NetworkMonitor`'s approach).
actor DiskMonitor {
    // IOBlockStorageDriver statistics keys. These are #define string macros in
    // <IOKit/storage/IOBlockStorageDriver.h> that do not import into Swift, so we
    // reference them as literals.
    private static let statisticsKey = "Statistics"
    private static let bytesReadKey = "Bytes (Read)"
    private static let bytesWrittenKey = "Bytes (Write)"

    private var previousRead: UInt64?
    private var previousWrite: UInt64?
    private var history60s: [DiskActivityPoint] = []

    func snapshots(every interval: Duration = .seconds(1)) -> AsyncStream<DiskSnapshot> {
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

    func latestSnapshot() -> DiskSnapshot? {
        let now = Date()
        let volumes = collectVolumes()

        let (totalRead, totalWrite) = collectIOByteCounters()

        let readPerSecond: UInt64
        let writePerSecond: UInt64
        if let previousRead, let previousWrite {
            readPerSecond = totalRead >= previousRead ? totalRead - previousRead : 0
            writePerSecond = totalWrite >= previousWrite ? totalWrite - previousWrite : 0
        } else {
            // First sample establishes the baseline; report zero throughput.
            readPerSecond = 0
            writePerSecond = 0
        }
        previousRead = totalRead
        previousWrite = totalWrite

        history60s.append(
            DiskActivityPoint(
                timestamp: now,
                readBytesPerSecond: readPerSecond,
                writeBytesPerSecond: writePerSecond
            )
        )
        if history60s.count > 60 {
            history60s.removeFirst(history60s.count - 60)
        }

        return DiskSnapshot(
            timestamp: now,
            volumes: volumes,
            readBytesPerSecond: readPerSecond,
            writeBytesPerSecond: writePerSecond,
            history60s: history60s
        )
    }

    func read() async -> DiskMetrics {
        guard let snapshot = latestSnapshot() else { return .empty }
        let primary = snapshot.primaryVolume
        return DiskMetrics(
            usedPercent: primary?.usedPercent ?? 0,
            usedBytes: primary?.usedBytes ?? 0,
            totalBytes: primary?.totalBytes ?? 0,
            readBytesPerSecond: snapshot.readBytesPerSecond,
            writeBytesPerSecond: snapshot.writeBytesPerSecond
        )
    }

    // MARK: - Capacity

    private func collectVolumes() -> [DiskVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey,
            .volumeIsLocalKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        var volumes: [DiskVolume] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

            // Only surface browsable, local volumes that report a real capacity.
            let isBrowsable = values.volumeIsBrowsable ?? true
            let isLocal = values.volumeIsLocal ?? true
            guard isBrowsable, isLocal else { continue }

            guard let total = values.volumeTotalCapacity, total > 0 else { continue }
            let available = values.volumeAvailableCapacity ?? 0

            volumes.append(
                DiskVolume(
                    name: values.volumeName ?? url.lastPathComponent,
                    mountPoint: url.path,
                    totalBytes: UInt64(max(0, total)),
                    freeBytes: UInt64(max(0, available)),
                    isRemovable: values.volumeIsRemovable ?? false,
                    isInternal: values.volumeIsInternal ?? false
                )
            )
        }

        // Root first, then internal volumes, then the rest — by capacity within each group.
        volumes.sort { lhs, rhs in
            if (lhs.mountPoint == "/") != (rhs.mountPoint == "/") {
                return lhs.mountPoint == "/"
            }
            if lhs.isInternal != rhs.isInternal {
                return lhs.isInternal && !rhs.isInternal
            }
            return lhs.totalBytes > rhs.totalBytes
        }

        return volumes
    }

    // MARK: - Throughput (IOKit)

    /// Sums cumulative bytes-read / bytes-written across every block storage driver.
    private func collectIOByteCounters() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        let match = IOServiceMatching("IOBlockStorageDriver")
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator)
        guard status == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var unmanagedProps: Unmanaged<CFMutableDictionary>?
            let result = IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0)
            guard result == KERN_SUCCESS,
                  let properties = unmanagedProps?.takeRetainedValue() as? [String: Any],
                  let statistics = properties[Self.statisticsKey] as? [String: Any] else {
                continue
            }

            if let read = (statistics[Self.bytesReadKey] as? NSNumber)?.uint64Value {
                totalRead += read
            }
            if let written = (statistics[Self.bytesWrittenKey] as? NSNumber)?.uint64Value {
                totalWrite += written
            }
        }

        return (totalRead, totalWrite)
    }
}
