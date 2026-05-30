import Foundation
import Testing
@testable import iStatus_Monitor

struct AlertEngineTests {
    var defaults: UserDefaults!
    var engine: AlertEngine!

    init() {
        defaults = UserDefaults(suiteName: "AlertEngineTests-\(UUID().uuidString)")
        engine = AlertEngine(defaults: defaults)
    }

    // MARK: - Rule Management Tests

    @Test("getRules returns rules sorted alphabetically")
    func getRulesSorted() async {
        let rule1 = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            label: "Zebra CPU",
            enabled: true,
            cooldownSeconds: 60
        )
        let rule2 = AlertRule(
            id: UUID(),
            metric: .memory,
            condition: .above,
            threshold: 85,
            label: "Apple Memory",
            enabled: true,
            cooldownSeconds: 60
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
            label: "CPU Alert",
            enabled: true,
            cooldownSeconds: 60
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
            label: "CPU Alert",
            enabled: true,
            cooldownSeconds: 60
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
            label: "CPU Alert",
            enabled: true,
            cooldownSeconds: 60
        )

        await engine.upsertRule(rule)
        #expect((await engine.getRules()).count == 1)

        await engine.deleteRule(id: id)
        #expect((await engine.getRules()).count == 0)
    }

    // MARK: - History Tests

    @Test("getHistory returns entries sorted by date descending")
    func getHistorySorted() async throws {
        let engine = AlertEngine(defaults: defaults)

        let snapshot1 = createMockSnapshot(cpu: 50)
        let snapshot2 = createMockSnapshot(cpu: 90)

        await engine.evaluate(snapshot1)
        try await Task.sleep(nanoseconds: 10_000_000)

        await engine.evaluate(snapshot2)

        let history = await engine.getHistory()
        #expect(history.count >= 2)
        #expect(history[0].timestamp >= history[1].timestamp)
    }

    @Test("recentAlertCount filters by time window")
    func recentAlertCountFilters() async throws {
        let engine = AlertEngine(defaults: defaults)

        let snapshot = createMockSnapshot(cpu: 95)
        await engine.evaluate(snapshot)

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
            label: "High CPU",
            enabled: true,
            cooldownSeconds: 1
        )

        await engine.upsertRule(rule)

        let highCPU = createMockSnapshot(cpu: 95)
        await engine.evaluate(highCPU)

        let history = await engine.getHistory()
        #expect(history.contains { $0.message.contains("High CPU") })
    }

    @Test("evaluate does not trigger alert when CPU below threshold")
    func evaluateCPUBelowThreshold() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            label: "High CPU",
            enabled: true,
            cooldownSeconds: 1
        )

        await engine.upsertRule(rule)

        let lowCPU = createMockSnapshot(cpu: 30)
        await engine.evaluate(lowCPU)

        let history = await engine.getHistory()
        #expect(!history.contains { $0.message.contains("High CPU") })
    }

    @Test("evaluate respects cooldown period")
    func evaluateRespectsCooldown() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            label: "High CPU",
            enabled: true,
            cooldownSeconds: 5
        )

        await engine.upsertRule(rule)

        let highCPU = createMockSnapshot(cpu: 95)

        await engine.evaluate(highCPU)
        let history1 = await engine.getHistory()
        let count1 = history1.filter { $0.message.contains("High CPU") }.count

        await engine.evaluate(highCPU)
        let history2 = await engine.getHistory()
        let count2 = history2.filter { $0.message.contains("High CPU") }.count

        #expect(count1 == count2)
    }

    @Test("evaluate respects disabled rules")
    func evaluateRespectDisabledRules() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            label: "High CPU",
            enabled: false,
            cooldownSeconds: 1
        )

        await engine.upsertRule(rule)

        let highCPU = createMockSnapshot(cpu: 95)
        await engine.evaluate(highCPU)

        let history = await engine.getHistory()
        #expect(!history.contains { $0.message.contains("High CPU") })
    }

    @Test("evaluate triggers memory alert correctly")
    func evaluateMemoryAlert() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .memory,
            condition: .above,
            threshold: 80,
            label: "High Memory",
            enabled: true,
            cooldownSeconds: 1
        )

        await engine.upsertRule(rule)

        let highMemory = createMockSnapshot(memoryPercent: 85)
        await engine.evaluate(highMemory)

        let history = await engine.getHistory()
        #expect(history.contains { $0.message.contains("High Memory") })
    }

    @Test("evaluate triggers alert for below threshold condition")
    func evaluateBelowThreshold() async throws {
        let rule = AlertRule(
            id: UUID(),
            metric: .battery,
            condition: .below,
            threshold: 20,
            label: "Low Battery",
            enabled: true,
            cooldownSeconds: 1
        )

        await engine.upsertRule(rule)

        let lowBattery = createMockSnapshot(batteryPercent: 15)
        await engine.evaluate(lowBattery)

        let history = await engine.getHistory()
        #expect(history.contains { $0.message.contains("Low Battery") })
    }

    @Test("evaluate checks all enabled rules")
    func evaluateMultipleRules() async throws {
        let cpuRule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 80,
            label: "High CPU",
            enabled: true,
            cooldownSeconds: 1
        )

        let memoryRule = AlertRule(
            id: UUID(),
            metric: .memory,
            condition: .above,
            threshold: 75,
            label: "High Memory",
            enabled: true,
            cooldownSeconds: 1
        )

        await engine.upsertRule(cpuRule)
        await engine.upsertRule(memoryRule)

        let snapshot = createMockSnapshot(cpu: 90, memoryPercent: 85)
        await engine.evaluate(snapshot)

        let history = await engine.getHistory()
        let cpuAlerts = history.filter { $0.message.contains("High CPU") }
        let memoryAlerts = history.filter { $0.message.contains("High Memory") }

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
            label: "CPU Warning",
            enabled: true,
            cooldownSeconds: 120
        )

        await engine.upsertRule(rule)

        let newEngine = AlertEngine(defaults: defaults)
        let rules = await newEngine.getRules()

        #expect(rules.count == 1)
        #expect(rules[0].id == id)
        #expect(rules[0].threshold == 85)
    }

    // MARK: - Helper Functions

    private func createMockSnapshot(
        cpu: Double = 50,
        memoryPercent: Double = 50,
        batteryPercent: Double = 80
    ) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUMetrics(usagePercent: cpu, coreCount: 8, temperatureCelsius: nil),
            ram: RAMMetrics(usedPercent: memoryPercent, usedBytes: 0, totalBytes: 0),
            battery: BatteryMetrics(levelPercent: batteryPercent, isCharging: false, health: 100),
            network: NetworkMetrics(bytesInPerSecond: 0, bytesOutPerSecond: 0),
            gpu: GPUMetrics(usagePercent: 10),
            cpuSnapshot: CPUSnapshot(
                timestamp: Date(),
                perCoreUsage: [],
                overallLoad: Float(cpu) / 100,
                loadAverage: LoadAverage(one: 1.0, five: 1.0, fifteen: 1.0)
            ),
            memorySnapshot: MemorySnapshot(
                timestamp: Date(),
                totalBytes: 16_000_000_000,
                usedBytes: UInt64(Double(16_000_000_000) * memoryPercent / 100),
                wiredBytes: 0,
                appBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                freeBytes: 0,
                swapUsedBytes: 0,
                swapTotalBytes: 0,
                pressure: .normal
            ),
            batterySnapshot: BatterySnapshot(
                timestamp: Date(),
                levelPercent: Int(batteryPercent),
                isCharging: false,
                timeRemaining: 3600,
                cycleCount: 100,
                health: 90,
                condition: .good
            ),
            networkSnapshot: nil,
            gpuSnapshot: nil,
            thermalSnapshot: nil,
            timestamp: Date()
        )
    }
}
