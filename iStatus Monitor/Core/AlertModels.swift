import Foundation

enum MetricType: String, Codable, CaseIterable, Identifiable {
    case cpu
    case memory
    case temperature
    case battery
    case network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .temperature: "Temperature"
        case .battery: "Battery"
        case .network: "Network"
        }
    }

    var defaultRange: ClosedRange<Double> {
        switch self {
        case .cpu, .memory, .battery: 0 ... 100
        case .temperature: 20 ... 110
        case .network: 0 ... 5_000
        }
    }

    var unit: String {
        switch self {
        case .cpu, .memory, .battery: "%"
        case .temperature: "°C"
        case .network: "KB/s"
        }
    }
}

enum Condition: String, Codable, CaseIterable, Identifiable {
    case above
    case below

    var id: String { rawValue }
}

struct AlertRule: Codable, Identifiable, Equatable {
    let id: UUID
    var metric: MetricType
    var condition: Condition
    var threshold: Double
    var cooldown: TimeInterval
    var isEnabled: Bool
    var label: String

    static func defaultRules() -> [AlertRule] {
        [
            AlertRule(
                id: UUID(),
                metric: .cpu,
                condition: .above,
                threshold: 90,
                cooldown: 300,
                isEnabled: true,
                label: "CPU > 90% for 10s"
            ),
            AlertRule(
                id: UUID(),
                metric: .memory,
                condition: .above,
                threshold: 85,
                cooldown: 300,
                isEnabled: true,
                label: "Memory > 85%"
            ),
            AlertRule(
                id: UUID(),
                metric: .temperature,
                condition: .above,
                threshold: 85,
                cooldown: 300,
                isEnabled: true,
                label: "Temperature > 85°C"
            ),
            AlertRule(
                id: UUID(),
                metric: .battery,
                condition: .below,
                threshold: 15,
                cooldown: 300,
                isEnabled: true,
                label: "Battery < 15% (unplugged)"
            )
        ]
    }
}

struct AlertHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let metric: MetricType
    let observedValue: Double
    let ruleLabel: String
    let ruleID: UUID
}
