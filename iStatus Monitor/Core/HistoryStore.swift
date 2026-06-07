import Foundation
import SwiftData

@ModelActor
actor HistoryStore {
    private let encoder = JSONEncoder()

    private var lastPersistAt: Date?
    // Write-once during init, read-only afterward. `nonisolated(unsafe)` lets the
    // delegating initializer set it after `self.init(modelContainer:)` (a synchronous
    // actor init is nonisolated, so a plain isolated `var` can't be mutated there).
    private nonisolated(unsafe) var persistInterval: TimeInterval = 10

    /// Configurable-interval initializer (used by tests). Delegates to the
    /// `@ModelActor`-generated `init(modelContainer:)`, which creates the
    /// `ModelContext` on this actor's serial executor, then overrides the
    /// persist interval.
    init(modelContainer: ModelContainer, persistInterval: TimeInterval = 10) {
        self.init(modelContainer: modelContainer)
        self.persistInterval = persistInterval
    }

    func ingest(_ snapshot: SystemSnapshot, now: Date = Date()) async {
        if let lastPersistAt, now.timeIntervalSince(lastPersistAt) < persistInterval {
            return
        }
        lastPersistAt = now

        persist(metric: .cpu, value: snapshot.cpu.usagePercent, snapshot: snapshot, at: now)
        persist(metric: .memory, value: snapshot.ram.usedPercent, snapshot: snapshot, at: now)
        persist(metric: .network, value: Double(snapshot.network.bytesInPerSecond + snapshot.network.bytesOutPerSecond) / 1024.0, snapshot: snapshot, at: now)
        persist(metric: .battery, value: snapshot.battery.levelPercent, snapshot: snapshot, at: now)

        if let maxTemp = snapshot.thermalSnapshot?.sensors.map(\.celsius).max() {
            persist(metric: .temperature, value: maxTemp, snapshot: snapshot, at: now)
        }

        trimRollingWindow(reference: now)
        try? modelContext.save()
    }

    func history(for metric: MetricType, in interval: DateInterval) async -> [MetricRecord] {
        let descriptor = FetchDescriptor<MetricRecord>(
            predicate: #Predicate { record in
                record.metricType == metric.rawValue
                && record.timestamp >= interval.start
                && record.timestamp <= interval.end
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func dailyAverages(for metric: MetricType, days: Int) async -> [(Date, Double)] {
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return [] }
        let records = await history(for: metric, in: DateInterval(start: start, end: end))

        let grouped = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted().compactMap { day in
            guard let values = grouped[day]?.map(\.value), !values.isEmpty else { return nil }
            let avg = values.reduce(0, +) / Double(values.count)
            return (day, avg)
        }
    }

    func peakValues(for metric: MetricType, in interval: DateInterval) async -> (min: Double, max: Double, avg: Double) {
        let records = await history(for: metric, in: interval)
        let values = records.map(\.value)
        guard let min = values.min(), let max = values.max(), !values.isEmpty else {
            return (0, 0, 0)
        }
        let avg = values.reduce(0, +) / Double(values.count)
        return (min, max, avg)
    }

    func exportRecords(for metric: MetricType, in interval: DateInterval) async -> [MetricRecord] {
        await history(for: metric, in: interval)
    }

    private func persist(metric: MetricType, value: Double, snapshot: SystemSnapshot, at timestamp: Date) {
        let metadata = try? encoder.encode(snapshot)
        let record = MetricRecord(timestamp: timestamp, metricType: metric.rawValue, value: value, metadata: metadata)
        modelContext.insert(record)
    }

    private func trimRollingWindow(reference: Date) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: reference) else { return }

        let descriptor = FetchDescriptor<MetricRecord>(
            predicate: #Predicate { record in
                record.timestamp < cutoff
            }
        )

        if let old = try? modelContext.fetch(descriptor) {
            for record in old {
                modelContext.delete(record)
            }
        }
    }
}
