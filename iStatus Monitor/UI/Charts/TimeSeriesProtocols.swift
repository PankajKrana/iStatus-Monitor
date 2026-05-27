import Foundation

protocol TimeSeriesDataPoint {
    var timestamp: Date { get }
    var value: Double { get }
}

struct ScalarPoint: TimeSeriesDataPoint, Identifiable, Sendable, Equatable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}
