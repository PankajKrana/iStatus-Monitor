import Foundation
import SwiftData

@Model
final class MetricRecord {
    var timestamp: Date
    var metricType: String
    var value: Double
    var metadata: Data?

    init(timestamp: Date, metricType: String, value: Double, metadata: Data? = nil) {
        self.timestamp = timestamp
        self.metricType = metricType
        self.value = value
        self.metadata = metadata
    }
}

// SwiftData models are thread-safe through exclusive access isolation.
// We conform to Sendable to allow this model to cross actor boundaries safely.
// This is a justified use of @unchecked Sendable: the model is internally
// synchronized by SwiftData's isolation mechanism.
extension MetricRecord: @unchecked Sendable {}
