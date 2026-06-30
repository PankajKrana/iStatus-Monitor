import Foundation
import OSLog
import UserNotifications

actor AlertEngine {
    private let notifier: AlertNotifying
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults

    private let rulesKey = "alerts.rules"
    private let historyKey = "alerts.history"
    private let lastFiredKey = "alerts.lastFired"
    private let globalSnoozeKey = "alerts.globalSnooze"

    private var rules: [AlertRule]
    private var history: [AlertHistoryEntry]
    private var lastFired: [UUID: Date]
    /// When set to a future date, ALL alerts are silenced until it passes.
    /// Auto-resumes with no timer — `evaluate` just stops firing while active.
    private var globalSnoozeUntil: Date?

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

        globalSnoozeUntil = defaults.object(forKey: globalSnoozeKey) as? Date
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
            if status == .denied {
                Logger.alerts.notice("Notifications are denied; threshold alerts will not be delivered until re-enabled in System Settings")
            }
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

        let now = Date()
        // Global snooze silences everything until it passes (auto-resumes).
        let globallySnoozed = (globalSnoozeUntil ?? .distantPast) > now

        for rule in rules where rule.isEnabled {
            // Snoozed rules are skipped, and their sustained counter reset so the
            // snooze window doesn't bank toward an instant fire on resume.
            if globallySnoozed || rule.isSnoozed(asOf: now) {
                sustainedDuration[rule.id] = 0
                continue
            }
            guard let value = metricValue(for: rule.metric, in: snapshot), value.isFinite else { continue }
            guard shouldTrigger(rule: rule, value: value, snapshot: snapshot, interval: interval) else { continue }
            guard isCooldownSatisfied(for: rule) else { continue }

            await fire(rule: rule, observedValue: value)
        }
    }

    // MARK: - Snooze

    func snoozeRule(id: UUID, until: Date) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].snoozedUntil = until
        sustainedDuration[id] = 0
        persistRules()
        emitChange()
    }

    func clearSnooze(id: UUID) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].snoozedUntil = nil
        persistRules()
        emitChange()
    }

    func snoozeAll(until: Date) {
        globalSnoozeUntil = until
        defaults.set(until, forKey: globalSnoozeKey)
        emitChange()
    }

    func clearGlobalSnooze() {
        globalSnoozeUntil = nil
        defaults.removeObject(forKey: globalSnoozeKey)
        emitChange()
    }

    /// The active global-snooze date, or `nil` if none is set or it has elapsed.
    func currentGlobalSnooze() -> Date? {
        guard let until = globalSnoozeUntil, until > Date() else { return nil }
        return until
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
            // Read from the optional detailed snapshot so machines without a
            // battery (desktops) or a failed read (nil) skip battery rules
            // entirely, instead of comparing a synthesized 0% against a "below"
            // threshold and firing a false low-battery alert. This also matches
            // the source used by the charging-suppression guard above.
            return snapshot.batterySnapshot?.chargePercent
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
        guard delivered else {
            Logger.alerts.notice("Alert '\(rule.label, privacy: .public)' triggered but not delivered (notifications off); not recorded")
            return
        }
        Logger.alerts.info("Alert fired: '\(rule.label, privacy: .public)' \(rule.metric.rawValue, privacy: .public)=\(observedValue, privacy: .public)")

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

    private func persistRules() { persist(rules, forKey: rulesKey) }
    private func persistHistory() { persist(history, forKey: historyKey) }
    private func persistLastFired() { persist(lastFired, forKey: lastFiredKey) }

    /// Encode-and-store helper. Encoding a plain Codable to JSON effectively never
    /// fails, but if it ever does we lose alert state silently — so log it.
    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        do {
            defaults.set(try encoder.encode(value), forKey: key)
        } catch {
            Logger.alerts.error("Failed to persist '\(key, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }
}
