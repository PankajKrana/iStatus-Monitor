import Foundation
import UserNotifications

actor AlertEngine {
    private let notifier: AlertNotifying
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults

    private let rulesKey = "alerts.rules"
    private let historyKey = "alerts.history"
    private let lastFiredKey = "alerts.lastFired"

    private var rules: [AlertRule]
    private var history: [AlertHistoryEntry]
    private var lastFired: [UUID: Date]

    /// Per-rule accumulated time a rule's condition has held, for sustained
    /// ("for Ns") triggering. Keyed by rule id so multiple sustained rules — and
    /// multiple CPU rules — never share one counter (B4).
    private var sustainedDuration: [UUID: TimeInterval] = [:]

    /// Becomes true once the system authorization status is no longer
    /// `notDetermined`, so the per-tick `evaluate` path stops re-querying settings.
    private var authorizationResolved = false
    private var categoriesConfigured = false

    /// Observers notified whenever history changes (an alert fired). Lets the UI
    /// store refresh live instead of only on `onAppear`/save (B7).
    private var changeObservers: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(
        defaults: UserDefaults = .standard,
        seedDefaultRules: Bool = true,
        notifier: AlertNotifying = SystemNotifier()
    ) {
        self.defaults = defaults
        self.notifier = notifier

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
    }

    /// Requests notification authorization only while the status is still
    /// `notDetermined`. macOS shows its prompt exactly once for that state, so
    /// this is safe to call repeatedly: when already authorized or denied it is a
    /// cheap no-op. Unlike the previous version it never records "requested"
    /// before the system actually resolves, so a dismissed prompt is retried.
    func requestAuthorizationIfNeeded() async {
        if !categoriesConfigured {
            await notifier.configureCategories()
            categoriesConfigured = true
        }
        if authorizationResolved { return }
        let status = await notifier.authorizationStatus()
        guard status == .notDetermined else {
            authorizationResolved = true
            return
        }
        await notifier.requestAuthorization()
        authorizationResolved = true
    }

    /// Current system authorization status, surfaced to the UI so it can prompt
    /// the user to enable notifications in System Settings when delivery is off.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notifier.authorizationStatus()
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
        sustainedDuration[id] = nil
        persistRules()
    }

    func getHistory() -> [AlertHistoryEntry] {
        history.sorted { $0.timestamp > $1.timestamp }
    }

    /// A stream that emits each time an alert is recorded, so observers can
    /// refresh live. The returned stream removes its observer automatically when
    /// the consumer's task ends.
    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            changeObservers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeChangeObserver(id) }
            }
        }
    }

    private func removeChangeObserver(_ id: UUID) {
        changeObservers[id] = nil
    }

    private func emitChange() {
        for continuation in changeObservers.values {
            continuation.yield(())
        }
    }

    func recentAlertCount(last seconds: TimeInterval) -> Int {
        let cutoff = Date().addingTimeInterval(-seconds)
        return history.filter { $0.timestamp >= cutoff }.count
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
        emitChange()
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
        // Don't alert on "low battery" while charging/full — the user is already
        // addressing it.
        if rule.metric == .battery, rule.condition == .below,
           let battery = snapshot.batterySnapshot,
           battery.chargeState == .charging || battery.chargeState == .full {
            sustainedDuration[rule.id] = 0
            return false
        }

        let conditionMet: Bool
        switch rule.condition {
        case .above: conditionMet = value > rule.threshold
        case .below: conditionMet = value < rule.threshold
        }

        // Instantaneous rule.
        guard rule.sustainedFor > 0 else { return conditionMet }

        // Sustained rule: the condition must hold continuously for `sustainedFor`
        // seconds. Duration is tracked per rule id (B4) and driven by an explicit
        // model field rather than parsing the label text (B3).
        if conditionMet {
            let elapsed = (sustainedDuration[rule.id] ?? 0) + interval
            sustainedDuration[rule.id] = elapsed
            return elapsed >= rule.sustainedFor
        } else {
            sustainedDuration[rule.id] = 0
            return false
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
        let conditionText = rule.condition == .above ? "above" : "below"
        let title = "⚠️ \(rule.metric.title) \(rule.condition == .above ? "High" : "Low")"
        let body = "\(rule.metric.title) is at \(formatted(value: observedValue, metric: rule.metric)) — \(conditionText) your \(formatted(value: rule.threshold, metric: rule.metric)) threshold"

        let delivered = await postNotification(
            title: title,
            body: body,
            categoryIdentifier: "ALERT_VIEW_DASHBOARD",
            threadIdentifier: rule.metric.rawValue
        )

        // Only advance the cooldown and record history once the notification is
        // actually delivered. Recording a "fired" alert the user never saw would
        // make history lie and could suppress a real, deliverable alert during the
        // cooldown window (B6).
        guard delivered else { return }

        lastFired[rule.id] = Date()
        persistLastFired()

        history.append(
            AlertHistoryEntry(
                id: UUID(),
                timestamp: Date(),
                metric: rule.metric,
                observedValue: observedValue,
                ruleLabel: rule.label,
                ruleID: rule.id,
                threshold: rule.threshold,
                condition: rule.condition
            )
        )

        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
        persistHistory()
        emitChange()
    }

    /// Posts a notification, returning whether it was actually handed to the
    /// system. Returns `false` when notifications are not authorized, so callers
    /// can avoid recording undelivered alerts.
    @discardableResult
    private func postNotification(
        title: String,
        body: String,
        categoryIdentifier: String,
        threadIdentifier: String? = nil,
        interruptionLevel: UNNotificationInterruptionLevel = .active
    ) async -> Bool {
        await notifier.deliver(
            AlertNotification(
                title: title,
                body: body,
                categoryIdentifier: categoryIdentifier,
                threadIdentifier: threadIdentifier,
                interruptionLevel: interruptionLevel
            )
        )
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
}
