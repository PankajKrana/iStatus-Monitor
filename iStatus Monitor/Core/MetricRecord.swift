import Foundation
import SwiftData

@Model
final class MetricRecord {
    var timestamp: Date
    var metricType: String
    var value: Double

    init(timestamp: Date, metricType: String, value: Double) {
        self.timestamp = timestamp
        self.metricType = metricType
        self.value = value
    }
}

/// Immutable, `Sendable` value type representing one persisted metric sample.
///
/// SwiftData `@Model` objects are bound to the `ModelContext` (and its actor)
/// that created them and must not be read from another isolation domain, so
/// `HistoryStore` maps its rows to this DTO before returning them across the
/// actor boundary. This replaces the previous `@unchecked Sendable` conformance
/// on `MetricRecord`, which let live model objects escape the store's actor.
struct MetricSample: Sendable, Identifiable, Equatable {
    let timestamp: Date
    let metricType: String
    let value: Double

    var id: Date { timestamp }
}
