import Foundation
import SwiftData

@ModelActor
actor HistoryStore {
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

        persist(metric: .cpu, value: snapshot.cpu.usagePercent, at: now)
        persist(metric: .memory, value: snapshot.ram.usedPercent, at: now)
        persist(metric: .network, value: Double(snapshot.network.bytesInPerSecond + snapshot.network.bytesOutPerSecond) / 1024.0, at: now)
        persist(metric: .battery, value: snapshot.battery.levelPercent, at: now)

        if let maxTemp = snapshot.thermalSnapshot?.sensors.map(\.celsius).max() {
            persist(metric: .temperature, value: maxTemp, at: now)
        }

        trimRollingWindow(reference: now)
        try? modelContext.save()
    }

    func history(for metric: MetricType, in interval: DateInterval) async -> [MetricSample] {
        let descriptor = FetchDescriptor<MetricRecord>(
            predicate: #Predicate { record in
                record.metricType == metric.rawValue
                && record.timestamp >= interval.start
                && record.timestamp <= interval.end
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        // Map to a Sendable value type before crossing the actor boundary —
        // live @Model objects must not escape the ModelContext's isolation.
        return records.map { MetricSample(timestamp: $0.timestamp, metricType: $0.metricType, value: $0.value) }
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

    func exportRecords(for metric: MetricType, in interval: DateInterval) async -> [MetricSample] {
        await history(for: metric, in: interval)
    }

    private func persist(metric: MetricType, value: Double, at timestamp: Date) {
        // Only the scalar `value` is stored. The previous implementation encoded
        // the entire SystemSnapshot into `metadata` on every record (5×/tick),
        // which was never read back and bloated the store to GB scale.
        let record = MetricRecord(timestamp: timestamp, metricType: metric.rawValue, value: value)
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
