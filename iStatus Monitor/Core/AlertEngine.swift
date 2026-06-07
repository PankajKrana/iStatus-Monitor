import Foundation
import UserNotifications

actor AlertEngine {
    private let center = UNUserNotificationCenter.current()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults

    private let rulesKey = "alerts.rules"
    private let historyKey = "alerts.history"
    private let lastFiredKey = "alerts.lastFired"
    private let permissionKey = "alerts.permission.requested"

    private var rules: [AlertRule]
    private var history: [AlertHistoryEntry]
    private var lastFired: [UUID: Date]
    private var cpuAboveDuration: TimeInterval = 0

    init(defaults: UserDefaults = .standard, seedDefaultRules: Bool = true) {
        self.defaults = defaults

        if let data = defaults.data(forKey: rulesKey),
           let decoded = try? decoder.decode([AlertRule].self, from: data) {
            rules = decoded
        } else {
            rules = seedDefaultRules ? AlertRule.defaultRules() : []
        }

        if let data = defaults.data(forKey: historyKey),
           let decoded = try? decoder.decode([AlertHistoryEntry].self, from: data) {
            history = decoded
        } else {
            history = []
        }

        if let data = defaults.data(forKey: lastFiredKey),
           let decoded = try? decoder.decode([UUID: Date].self, from: data) {
            lastFired = decoded
        } else {
            lastFired = [:]
        }

        configureNotificationCategories()
    }

    func requestAuthorizationIfNeeded() async {
        if defaults.bool(forKey: permissionKey) { return }
        defaults.set(true, forKey: permissionKey)
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func getRules() -> [AlertRule] {
        rules.sorted { $0.label < $1.label }
    }

    func upsertRule(_ rule: AlertRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else {
            rules.append(rule)
        }
        persistRules()
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        persistRules()
    }

    func getHistory() -> [AlertHistoryEntry] {
        history.sorted { $0.timestamp > $1.timestamp }
    }

    func recentAlertCount(last seconds: TimeInterval) -> Int {
        let cutoff = Date().addingTimeInterval(-seconds)
        return history.filter { $0.timestamp >= cutoff }.count
    }

    func evaluate(_ snapshot: SystemSnapshot, interval: TimeInterval = 1) async {
        await requestAuthorizationIfNeeded()

        for rule in rules where rule.isEnabled {
            guard let value = metricValue(for: rule.metric, in: snapshot) else { continue }
            guard shouldTrigger(rule: rule, value: value, snapshot: snapshot, interval: interval) else { continue }
            guard isCooldownSatisfied(for: rule) else { continue }

            await fire(rule: rule, observedValue: value)
        }
    }

    func fireTestAlert(ruleID: UUID) async {
        guard let rule = rules.first(where: { $0.id == ruleID }) else { return }
        await requestAuthorizationIfNeeded()
        await postNotification(
            title: "⚠️ Test: \(rule.label)",
            body: "This is a test alert for your \(rule.metric.title) rule.",
            categoryIdentifier: "ALERT_VIEW_DASHBOARD"
        )
    }

    private func shouldTrigger(rule: AlertRule, value: Double, snapshot: SystemSnapshot, interval: TimeInterval) -> Bool {
        switch rule.metric {
        case .battery:
            if rule.condition == .below,
               let battery = snapshot.batterySnapshot,
               battery.chargeState == .charging || battery.chargeState == .full {
                return false
            }

        default:
            break
        }

        switch (rule.metric, rule.condition) {
        case (.cpu, .above):
            if value > rule.threshold {
                cpuAboveDuration += interval
            } else {
                cpuAboveDuration = 0
            }
            if rule.label.localizedCaseInsensitiveContains("for 10s") {
                return cpuAboveDuration >= 10
            }
            return value > rule.threshold

        default:
            switch rule.condition {
            case .above: return value > rule.threshold
            case .below: return value < rule.threshold
            }
        }
    }

    private func metricValue(for metric: MetricType, in snapshot: SystemSnapshot) -> Double? {
        switch metric {
        case .cpu:
            return snapshot.cpu.usagePercent
        case .memory:
            return snapshot.ram.usedPercent
        case .temperature:
            return snapshot.thermalSnapshot?.sensors.map(\.celsius).max()
        case .battery:
            return snapshot.battery.levelPercent
        case .network:
            let kbps = Double(snapshot.network.bytesInPerSecond + snapshot.network.bytesOutPerSecond) / 1024
            return kbps
        }
    }

    private func isCooldownSatisfied(for rule: AlertRule) -> Bool {
        guard let last = lastFired[rule.id] else { return true }
        return Date().timeIntervalSince(last) >= rule.cooldown
    }

    private func fire(rule: AlertRule, observedValue: Double) async {
        lastFired[rule.id] = Date()
        persistLastFired()

        let conditionText = rule.condition == .above ? "above" : "below"
        let title = "⚠️ \(rule.metric.title) \(rule.condition == .above ? "High" : "Low")"
        let body = "\(rule.metric.title) is at \(formatted(value: observedValue, metric: rule.metric)) — \(conditionText) your \(formatted(value: rule.threshold, metric: rule.metric)) threshold"

        await postNotification(title: title, body: body, categoryIdentifier: "ALERT_VIEW_DASHBOARD")

        history.append(
            AlertHistoryEntry(
                id: UUID(),
                timestamp: Date(),
                metric: rule.metric,
                observedValue: observedValue,
                ruleLabel: rule.label,
                ruleID: rule.id
            )
        )

        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
        persistHistory()
    }

    private func postNotification(title: String, body: String, categoryIdentifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    private func formatted(value: Double, metric: MetricType) -> String {
        switch metric {
        case .cpu, .memory, .battery:
            return String(format: "%.0f%%", value)
        case .temperature:
            return String(format: "%.1f°C", value)
        case .network:
            return String(format: "%.0f KB/s", value)
        }
    }

    private func persistRules() {
        if let data = try? encoder.encode(rules) {
            defaults.set(data, forKey: rulesKey)
        }
    }

    private func persistHistory() {
        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func persistLastFired() {
        if let data = try? encoder.encode(lastFired) {
            defaults.set(data, forKey: lastFiredKey)
        }
    }

    private func configureNotificationCategories() {
        let viewAction = UNNotificationAction(identifier: "VIEW_DASHBOARD", title: "View Dashboard", options: [.foreground])
        let category = UNNotificationCategory(identifier: "ALERT_VIEW_DASHBOARD", actions: [viewAction], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }
}
