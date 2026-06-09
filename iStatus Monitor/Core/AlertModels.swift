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

    /// SF Symbol used across the alerts UI for this metric.
    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .temperature: "thermometer.medium"
        case .battery: "battery.25"
        case .network: "network"
        }
    }
}

/// Visual severity of an alert, used purely for presentation (color + glyph +
/// sorting). Derived from how far an observed value exceeded its threshold.
enum AlertSeverity: Int, Comparable, CaseIterable, Identifiable {
    case info
    case warning
    case critical

    var id: Int { rawValue }

    static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
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
    /// How long (seconds) the condition must hold continuously before the alert
    /// fires. `0` means fire immediately. Replaces the old label-string parsing
    /// for sustained triggering (B3).
    var sustainedFor: TimeInterval

    init(
        id: UUID,
        metric: MetricType,
        condition: Condition,
        threshold: Double,
        cooldown: TimeInterval,
        isEnabled: Bool,
        label: String,
        sustainedFor: TimeInterval = 0
    ) {
        self.id = id
        self.metric = metric
        self.condition = condition
        self.threshold = threshold
        self.cooldown = cooldown
        self.isEnabled = isEnabled
        self.label = label
        self.sustainedFor = sustainedFor
    }

    private enum CodingKeys: String, CodingKey {
        case id, metric, condition, threshold, cooldown, isEnabled, label, sustainedFor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        metric = try c.decode(MetricType.self, forKey: .metric)
        condition = try c.decode(Condition.self, forKey: .condition)
        threshold = try c.decode(Double.self, forKey: .threshold)
        cooldown = try c.decode(TimeInterval.self, forKey: .cooldown)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        label = try c.decode(String.self, forKey: .label)
        // Back-compat: rules persisted before `sustainedFor` existed have no key.
        // Preserve the one legacy sustained rule (its label said "for 10s") so an
        // upgrade doesn't silently turn it instantaneous; everything else is 0.
        if let stored = try c.decodeIfPresent(TimeInterval.self, forKey: .sustainedFor) {
            sustainedFor = stored
        } else {
            sustainedFor = label.localizedCaseInsensitiveContains("for 10s") ? 10 : 0
        }
    }

    static func defaultRules() -> [AlertRule] {
        [
            AlertRule(
                id: UUID(),
                metric: .cpu,
                condition: .above,
                threshold: 90,
                cooldown: 300,
                isEnabled: true,
                label: "CPU > 90% for 10s",
                sustainedFor: 10
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
    /// Threshold/condition captured at fire time, so the detail view can show
    /// "observed vs threshold" and severity can be computed. Optional for
    /// back-compat with entries persisted before these fields existed.
    let threshold: Double?
    let condition: Condition?

    init(
        id: UUID,
        timestamp: Date,
        metric: MetricType,
        observedValue: Double,
        ruleLabel: String,
        ruleID: UUID,
        threshold: Double? = nil,
        condition: Condition? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.metric = metric
        self.observedValue = observedValue
        self.ruleLabel = ruleLabel
        self.ruleID = ruleID
        self.threshold = threshold
        self.condition = condition
    }

    /// Severity from how far the observed value crossed the threshold. Without
    /// threshold context (legacy entries) an alert is treated as a warning.
    var severity: AlertSeverity {
        guard let threshold, let condition, threshold != 0 else { return .warning }
        let exceedance: Double
        switch condition {
        case .above: exceedance = (observedValue - threshold) / abs(threshold)
        case .below: exceedance = (threshold - observedValue) / abs(threshold)
        }
        if exceedance >= 0.12 { return .critical }
        if exceedance >= 0 { return .warning }
        return .info
    }
}
