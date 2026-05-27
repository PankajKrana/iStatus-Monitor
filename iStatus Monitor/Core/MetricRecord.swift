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

extension MetricRecord: @unchecked Sendable {}
