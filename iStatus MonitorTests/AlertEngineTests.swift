import Foundation
import Testing
import UserNotifications
@testable import iStatus_Monitor

/// Test double that reports notifications as authorized and always delivers, so
/// the engine's record-on-delivery path runs deterministically without a live
/// `UNUserNotificationCenter`.
actor StubNotifier: AlertNotifying {
    private(set) var delivered: [AlertNotification] = []

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async {}
    func configureCategories() async {}

    @discardableResult
    func deliver(_ notification: AlertNotification) async -> Bool {
        delivered.append(notification)
        return true
    }
}

/// Test double simulating notifications being denied: delivery always fails.
actor DenyingNotifier: AlertNotifying {
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func requestAuthorization() async {}
    func configureCategories() async {}
    @discardableResult
    func deliver(_ notification: AlertNotification) async -> Bool { false }
}

@MainActor
struct AlertEngineTests {
    let suiteName: String
    var defaults: UserDefaults!
    var engine: AlertEngine!

    init() {
        suiteName = "AlertEngineTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        engine = AlertEngine(defaults: defaults, seedDefaultRules: false, notifier: StubNotifier())
    }

    /// A fresh `UserDefaults` bound to a test suite. Used to build a second engine
    /// inside `async` test methods: a locally-created instance lives in its own
    /// isolation region and can be sent into the `AlertEngine` actor, whereas the
    /// `@MainActor`-isolated `self.defaults` cannot (Swift 6 region checking). It's
    /// `nonisolated static` so the returned value is disconnected from `self`'s
    /// region. Same suite name → same backing store, so persistence still holds.
    nonisolated private static func makeDefaults(suite: String) -> UserDefaults {
        UserDefaults(suiteName: suite)!
    }

    // MARK: - Rule Management Tests

    @Test("getRules returns rules sorted alphabetically")
    func getRulesSorted() async {
        let rule1 = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 60,
            isEnabled: true,
            label: "Zebra CPU"
        )
        let rule2 = AlertRule(
            id: UUID(),
            metric: .memory,
            condition: .above,
            threshold: 85,
            cooldown: 60,
            isEnabled: true,
            label: "Apple Memory"
        )

        await engine.upsertRule(rule1)
        await engine.upsertRule(rule2)

        let rules = await engine.getRules()
        #expect(rules.count == 2)
        #expect(rules[0].label == "Apple Memory")
        #expect(rules[1].label == "Zebra CPU")
    }

    @Test("upsertRule creates new rule when not exists")
    func upsertRuleCreatesNew() async {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 60,
            isEnabled: true,
            label: "CPU Alert"
        )

        await engine.upsertRule(rule)
        let rules = await engine.getRules()
        #expect(rules.count == 1)
        #expect(rules[0].id == rule.id)
    }

    @Test("upsertRule updates existing rule")
    func upsertRuleUpdatesExisting() async {
        let id = UUID()
        var rule = AlertRule(
            id: id,
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 60,
            isEnabled: true,
            label: "CPU Alert"
        )

        await engine.upsertRule(rule)

        rule.threshold = 90
        await engine.upsertRule(rule)

        let rules = await engine.getRules()
        #expect(rules.count == 1)
        #expect(rules[0].threshold == 90)
    }

    @Test("deleteRule removes rule by id")
    func deleteRuleRemovesById() async {
        let id = UUID()
        let rule = AlertRule(
            id: id,
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 60,
            isEnabled: true,
            label: "CPU Alert"
        )

        await engine.upsertRule(rule)
        #expect((await engine.getRules()).count == 1)

        await engine.deleteRule(id: id)
        #expect((await engine.getRules()).count == 0)
    }

    // MARK: - History Tests

    @Test("getHistory returns entries sorted by date descending")
    func getHistorySorted() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 40,
            cooldown: 0,
            isEnabled: true,
            label: "CPU Activity"
        )
        await engine.upsertRule(rule)

        await engine.evaluate(createMockSnapshot(cpu: 50))
        try await Task.sleep(nanoseconds: 10_000_000)
        await engine.evaluate(createMockSnapshot(cpu: 90))

        let history = await engine.getHistory()
        #expect(history.count >= 2)
        #expect(history[0].timestamp >= history[1].timestamp)
    }

    @Test("recentAlertCount filters by time window")
    func recentAlertCountFilters() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 50,
            cooldown: 0,
            isEnabled: true,
            label: "CPU High"
        )
        await engine.upsertRule(rule)

        await engine.evaluate(createMockSnapshot(cpu: 95))

        let count30s = await engine.recentAlertCount(last: 30)
        let count1h = await engine.recentAlertCount(last: 3600)

        #expect(count30s <= count1h)
    }

    // MARK: - Rule Evaluation Tests

    @Test("evaluate triggers alert when CPU above threshold")
    func evaluateCPUAboveThreshold() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 1,
            isEnabled: true,
            label: "High CPU"
        )

        await engine.upsertRule(rule)

        let highCPU = createMockSnapshot(cpu: 95)
        await engine.evaluate(highCPU)

        let history = await engine.getHistory()
        #expect(history.contains { $0.ruleLabel.contains("High CPU") })
    }

    @Test("evaluate does not trigger alert when CPU below threshold")
    func evaluateCPUBelowThreshold() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 1,
            isEnabled: true,
            label: "High CPU"
        )

        await engine.upsertRule(rule)

        let lowCPU = createMockSnapshot(cpu: 30)
        await engine.evaluate(lowCPU)

        let history = await engine.getHistory()
        #expect(!history.contains { $0.ruleLabel.contains("High CPU") })
    }

    @Test("evaluate respects cooldown period")
    func evaluateRespectsCooldown() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 5,
            isEnabled: true,
            label: "High CPU"
        )

        await engine.upsertRule(rule)

        let highCPU = createMockSnapshot(cpu: 95)

        await engine.evaluate(highCPU)
        let history1 = await engine.getHistory()
        let count1 = history1.filter { $0.ruleLabel.contains("High CPU") }.count

        await engine.evaluate(highCPU)
        let history2 = await engine.getHistory()
        let count2 = history2.filter { $0.ruleLabel.contains("High CPU") }.count

        #expect(count1 == count2)
    }

    @Test("evaluate respects disabled rules")
    func evaluateRespectDisabledRules() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 1,
            isEnabled: false,
            label: "High CPU"
        )

        await engine.upsertRule(rule)

        let highCPU = createMockSnapshot(cpu: 95)
        await engine.evaluate(highCPU)

        let history = await engine.getHistory()
        #expect(!history.contains { $0.ruleLabel.contains("High CPU") })
    }

    @Test("evaluate triggers memory alert correctly")
    func evaluateMemoryAlert() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .memory,
            condition: .above,
            threshold: 80,
            cooldown: 1,
            isEnabled: true,
            label: "High Memory"
        )

        await engine.upsertRule(rule)

        let highMemory = createMockSnapshot(memoryPercent: 85)
        await engine.evaluate(highMemory)

        let history = await engine.getHistory()
        #expect(history.contains { $0.ruleLabel.contains("High Memory") })
    }

    @Test("evaluate triggers alert for below threshold condition")
    func evaluateBelowThreshold() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .battery,
            condition: .below,
            threshold: 20,
            cooldown: 1,
            isEnabled: true,
            label: "Low Battery"
        )

        await engine.upsertRule(rule)

        let lowBattery = createMockSnapshot(batteryPercent: 15)
        await engine.evaluate(lowBattery)

        let history = await engine.getHistory()
        #expect(history.contains { $0.ruleLabel.contains("Low Battery") })
    }

    @Test("evaluate checks all enabled rules")
    func evaluateMultipleRules() async throws {
        let cpuRule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 1,
            isEnabled: true,
            label: "High CPU"
        )

        let memoryRule = AlertRule(
            id: UUID(),
            metric: .memory,
            condition: .above,
            threshold: 75,
            cooldown: 1,
            isEnabled: true,
            label: "High Memory"
        )

        await engine.upsertRule(cpuRule)
        await engine.upsertRule(memoryRule)

        let snapshot = createMockSnapshot(cpu: 90, memoryPercent: 85)
        await engine.evaluate(snapshot)

        let history = await engine.getHistory()
        let cpuAlerts = history.filter { $0.ruleLabel.contains("High CPU") }
        let memoryAlerts = history.filter { $0.ruleLabel.contains("High Memory") }

        #expect(cpuAlerts.count > 0)
        #expect(memoryAlerts.count > 0)
    }

    @Test("rules persist to UserDefaults")
    func rulesPersistence() async throws {
        let id = UUID()
        let rule = AlertRule(
            id: id,
            metric: .cpu,
            condition: .above,
            threshold: 85,
            cooldown: 120,
            isEnabled: true,
            label: "CPU Warning"
        )

        await engine.upsertRule(rule)

        let newEngine = AlertEngine(defaults: Self.makeDefaults(suite: suiteName), seedDefaultRules: false, notifier: StubNotifier())
        let rules = await newEngine.getRules()

        #expect(rules.count == 1)
        #expect(rules[0].id == id)
        #expect(rules[0].threshold == 85)
    }

    // MARK: - Sustained Duration Tests (B3/B4)

    @Test("sustainedFor rule does not fire until the duration elapses")
    func sustainedRuleWaitsForDuration() async {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 0,
            isEnabled: true,
            label: "Sustained CPU",
            sustainedFor: 3
        )
        await engine.upsertRule(rule)

        // Each evaluate represents one 1s interval above threshold.
        await engine.evaluate(createMockSnapshot(cpu: 95), interval: 1)
        #expect((await engine.getHistory()).isEmpty)            // 1s elapsed
        await engine.evaluate(createMockSnapshot(cpu: 95), interval: 1)
        #expect((await engine.getHistory()).isEmpty)            // 2s elapsed
        await engine.evaluate(createMockSnapshot(cpu: 95), interval: 1)
        #expect(!(await engine.getHistory()).isEmpty)           // 3s elapsed -> fires
    }

    @Test("dropping below threshold resets the sustained timer")
    func sustainedRuleResetsOnDrop() async {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            cooldown: 0,
            isEnabled: true,
            label: "Sustained CPU",
            sustainedFor: 3
        )
        await engine.upsertRule(rule)

        await engine.evaluate(createMockSnapshot(cpu: 95), interval: 1)  // 1s
        await engine.evaluate(createMockSnapshot(cpu: 10), interval: 1)  // reset
        await engine.evaluate(createMockSnapshot(cpu: 95), interval: 1)  // 1s again
        await engine.evaluate(createMockSnapshot(cpu: 95), interval: 1)  // 2s
        #expect((await engine.getHistory()).isEmpty)
    }

    @Test("two CPU rules track sustained duration independently (B4)")
    func sustainedRulesDoNotShareCounter() async {
        let fast = AlertRule(
            id: UUID(), metric: .cpu, condition: .above, threshold: 80,
            cooldown: 0, isEnabled: true, label: "Fast", sustainedFor: 1
        )
        let slow = AlertRule(
            id: UUID(), metric: .cpu, condition: .above, threshold: 80,
            cooldown: 0, isEnabled: true, label: "Slow", sustainedFor: 5
        )
        await engine.upsertRule(fast)
        await engine.upsertRule(slow)

        await engine.evaluate(createMockSnapshot(cpu: 95), interval: 1)

        let history = await engine.getHistory()
        // After 1s only the 1s rule should have fired — proving the counter is
        // per-rule, not shared/double-incremented across both CPU rules.
        #expect(history.contains { $0.ruleLabel == "Fast" })
        #expect(!history.contains { $0.ruleLabel == "Slow" })
    }

    @Test("legacy rule without sustainedFor key migrates the 'for 10s' default")
    func legacyDurationMigration() throws {
        let json = """
        {"id":"\(UUID().uuidString)","metric":"cpu","condition":"above",
         "threshold":90,"cooldown":300,"isEnabled":true,"label":"CPU > 90% for 10s"}
        """
        let rule = try JSONDecoder().decode(AlertRule.self, from: Data(json.utf8))
        #expect(rule.sustainedFor == 10)
    }

    // MARK: - Delivery Tests (B6)

    @Test("history is not recorded when notifications are unauthorized")
    func unauthorizedDeliveryRecordsNothing() async {
        let denying = DenyingNotifier()
        let denyEngine = AlertEngine(defaults: Self.makeDefaults(suite: suiteName), seedDefaultRules: false, notifier: denying)
        let rule = AlertRule(
            id: UUID(), metric: .cpu, condition: .above, threshold: 80,
            cooldown: 0, isEnabled: true, label: "CPU"
        )
        await denyEngine.upsertRule(rule)

        await denyEngine.evaluate(createMockSnapshot(cpu: 95))

        #expect((await denyEngine.getHistory()).isEmpty)
    }

    // MARK: - Helper Functions

    private func createMockSnapshot(
        cpu: Double = 50,
        memoryPercent: Double = 50,
        batteryPercent: Double = 80
    ) -> SystemSnapshot {
        let totalBytes: UInt64 = 16_000_000_000
        return SystemSnapshot(
            timestamp: Date(),
            cpu: CPUMetrics(usagePercent: cpu, coreCount: 8, temperatureCelsius: nil),
            cpuSnapshot: nil,
            ram: MemoryMetrics(usedBytes: UInt64(Double(totalBytes) * memoryPercent / 100), totalBytes: totalBytes),
            memorySnapshot: nil,
            battery: BatteryMetrics(levelPercent: batteryPercent, isCharging: false, cycleCount: 100),
            batterySnapshot: BatterySnapshot(
                timestamp: Date(),
                currentCapacitymAh: 5000,
                designCapacitymAh: 6000,
                healthPercent: 90,
                cycleCount: 100,
                chargeState: .discharging,
                chargePercent: batteryPercent,
                timeToEmptyMinutes: 120,
                timeToFullMinutes: nil,
                voltageMillivolts: 12_000,
                amperageMilliamps: -1000,
                watts: 12,
                temperatureCelsius: 30,
                temperatureFahrenheit: 86,
                serialNumber: "TEST",
                chargeHistory24h: [],
                healthHistory: []
            ),
            network: NetworkMetrics(bytesInPerSecond: 0, bytesOutPerSecond: 0, primaryInterface: "en0"),
            networkSnapshot: nil,
            gpu: GPUMetrics(usagePercent: 10, temperatureCelsius: nil),
            gpuSnapshot: nil,
            disk: .empty,
            diskSnapshot: nil,
            thermalSnapshot: nil
        )
    }
}
