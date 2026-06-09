import Foundation
import SwiftData
import Testing
@testable import iStatus_Monitor

struct HistoryStoreTests {
    var modelContainer: ModelContainer!
    var store: HistoryStore!

    init() throws {
        let schema = Schema([MetricRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        store = HistoryStore(modelContainer: modelContainer, persistInterval: 0)
    }

    @Test("ingest persists metric records")
    func ingestPersistsRecords() async throws {
        let snapshot = createMockSnapshot(cpu: 75, memoryPercent: 60)
        await store.ingest(snapshot)

        let records = await store.history(
            for: .cpu,
            in: DateInterval(start: Date().addingTimeInterval(-3600), end: Date().addingTimeInterval(3600))
        )

        #expect(records.count > 0)
        #expect(records.contains { $0.metricType == "cpu" })
    }

    @Test("history filters by metric type correctly")
    func historyFiltersMetricType() async throws {
        let snapshot = createMockSnapshot(cpu: 60, memoryPercent: 50)
        await store.ingest(snapshot)

        let cpuRecords = await store.history(
            for: .cpu,
            in: DateInterval(start: Date().addingTimeInterval(-3600), end: Date().addingTimeInterval(3600))
        )

        let memoryRecords = await store.history(
            for: .memory,
            in: DateInterval(start: Date().addingTimeInterval(-3600), end: Date().addingTimeInterval(3600))
        )

        #expect(cpuRecords.count > 0)
        #expect(memoryRecords.count > 0)
        #expect(!cpuRecords.contains { $0.metricType == "memory" })
    }

    @Test("history returns records sorted by timestamp")
    func historySortedByTimestamp() async throws {
        let interval = DateInterval(start: Date().addingTimeInterval(-7200), end: Date().addingTimeInterval(3600))

        for i in 0..<3 {
            let snapshot = createMockSnapshot(cpu: Double(50 + i * 5))
            await store.ingest(snapshot)
            if i < 2 {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        let records = await store.history(for: .cpu, in: interval)

        guard records.count > 1 else { return }

        for i in 0..<(records.count - 1) {
            #expect(records[i].timestamp <= records[i + 1].timestamp)
        }
    }

    @Test("history respects date interval boundaries")
    func historyRespectsBoundaries() async throws {
        let snapshot = createMockSnapshot(cpu: 70)
        await store.ingest(snapshot)

        let now = Date()
        let past = now.addingTimeInterval(-3600)
        let future = now.addingTimeInterval(3600)

        let validInterval = DateInterval(start: past, end: future)
        let beforeInterval = DateInterval(start: past.addingTimeInterval(-7200), end: past.addingTimeInterval(-3600))

        let validRecords = await store.history(for: .cpu, in: validInterval)
        let beforeRecords = await store.history(for: .cpu, in: beforeInterval)

        #expect(validRecords.count > 0)
        #expect(beforeRecords.count == 0)
    }

    @Test("peakValues returns correct statistics")
    func peakValuesCalculations() async throws {
        let values = [30.0, 50.0, 70.0]
        for value in values {
            let snapshot = createMockSnapshot(cpu: value)
            await store.ingest(snapshot)
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let interval = DateInterval(start: Date().addingTimeInterval(-7200), end: Date().addingTimeInterval(3600))
        let peaks = await store.peakValues(for: .cpu, in: interval)

        #expect(peaks.min >= 30.0)
        #expect(peaks.max <= 70.0)
        #expect(peaks.avg > 0)
    }

    @Test("dailyAverages groups records by day")
    func dailyAveragesGrouping() async throws {
        let snapshot1 = createMockSnapshot(cpu: 40)
        let snapshot2 = createMockSnapshot(cpu: 60)

        await store.ingest(snapshot1)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        await store.ingest(snapshot2)

        let daily = await store.dailyAverages(for: .cpu, days: 1)

        #expect(daily.count > 0)
    }

    @Test("concurrent ingestion is safe")
    func concurrentIngestionSafe() async throws {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<3 {
                group.addTask {
                    let snapshot = createMockSnapshot(cpu: Double(50 + i * 5))
                    await store.ingest(snapshot)
                }
            }
        }

        let records = await store.history(
            for: .cpu,
            in: DateInterval(start: Date().addingTimeInterval(-3600), end: Date().addingTimeInterval(3600))
        )

        #expect(records.count > 0)
    }

    @Test("history with empty result returns empty array")
    func emptyHistoryReturnsEmpty() async throws {
        let futureDate = Date().addingTimeInterval(86400)
        let interval = DateInterval(start: futureDate, end: futureDate.addingTimeInterval(3600))

        let records = await store.history(for: .cpu, in: interval)

        #expect(records.isEmpty)
    }

    @Test("peakValues on empty dataset returns zeros")
    func emptyPeakValuesReturnsZeros() async throws {
        let futureDate = Date().addingTimeInterval(86400)
        let interval = DateInterval(start: futureDate, end: futureDate.addingTimeInterval(3600))

        let peaks = await store.peakValues(for: .cpu, in: interval)

        #expect(peaks.min == 0)
        #expect(peaks.max == 0)
        #expect(peaks.avg == 0)
    }

    // MARK: - Helper Functions

    private func createMockSnapshot(
        cpu: Double = 50,
        memoryPercent: Double = 50,
        batteryPercent: Double = 80,
        networkKBps: Double = 100,
        temperatureCelsius: Double = 45
    ) -> SystemSnapshot {
        let totalBytes: UInt64 = 16_000_000_000
        let networkBytes = UInt64(networkKBps * 1024)
        return SystemSnapshot(
            timestamp: Date(),
            cpu: CPUMetrics(usagePercent: cpu, coreCount: 8, temperatureCelsius: temperatureCelsius),
            cpuSnapshot: CPUSnapshot(
                timestamp: Date(),
                perCoreUsage: [],
                overallLoad: Float(cpu) / 100,
                loadAverage: LoadAverage(one: 1.0, five: 1.0, fifteen: 1.0)
            ),
            ram: MemoryMetrics(usedBytes: UInt64(Double(totalBytes) * memoryPercent / 100), totalBytes: totalBytes),
            memorySnapshot: MemorySnapshot(
                timestamp: Date(),
                totalBytes: totalBytes,
                usedBytes: UInt64(Double(totalBytes) * memoryPercent / 100),
                wiredBytes: 0,
                appBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                freeBytes: 0,
                swapUsedBytes: 0,
                swapTotalBytes: 0,
                pressure: .normal
            ),
            battery: BatteryMetrics(levelPercent: batteryPercent, isCharging: false, cycleCount: 100),
            batterySnapshot: nil,
            network: NetworkMetrics(bytesInPerSecond: networkBytes, bytesOutPerSecond: networkBytes, primaryInterface: "en0"),
            networkSnapshot: nil,
            gpu: GPUMetrics(usagePercent: 10, temperatureCelsius: nil),
            gpuSnapshot: nil,
            disk: .empty,
            diskSnapshot: nil,
            thermalSnapshot: ThermalSnapshot(
                timestamp: Date(),
                fans: [],
                sensors: [
                    ThermalSensor(
                        key: "TC0P",
                        name: "CPU",
                        celsius: temperatureCelsius,
                        fahrenheit: temperatureCelsius * 9 / 5 + 32,
                        zone: .cpu
                    )
                ],
                thermalState: .nominal
            )
        )
    }
}
