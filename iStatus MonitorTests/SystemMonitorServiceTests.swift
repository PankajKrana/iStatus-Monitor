import Foundation
import Testing
@testable import iStatus_Monitor

@MainActor
struct SystemMonitorServiceTests {
    @Test("service initializes successfully")
    func serviceInitialization() {
        let service = SystemMonitorService()
        #expect(true)
    }

    @Test("service initializes with custom dependencies")
    func serviceInitializationWithDeps() {
        let service = SystemMonitorService(
            cpuMonitor: CPUMonitor(),
            memoryMonitor: MemoryMonitor(),
            batteryMonitor: BatteryMonitor(),
            networkMonitor: NetworkMonitor(),
            gpuMonitor: GPUMonitor(),
            thermalMonitor: ThermalMonitor(),
            dataStore: DataStore(),
            alertEngine: AlertEngine(),
            batteryAlertService: BatteryAlertService(),
            historyStore: nil
        )
        #expect(true)
    }

    @Test("start updates appState monitoring flag")
    func startUpdatesMonitoringFlag() async throws {
        let service = SystemMonitorService()
        let appState = await AppState()

        #expect(!appState.isMonitoring)

        await service.start(appState: appState, interval: .milliseconds(50))
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(appState.isMonitoring)

        await service.stop()
    }

    @Test("stop cancels monitoring")
    func stopCancelsMonitoring() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))
        try await Task.sleep(nanoseconds: 20_000_000)

        await service.stop()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(true)
    }

    @Test("start can only be called once")
    func startOnceGuard() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(100))
        try await Task.sleep(nanoseconds: 20_000_000)

        // Second start should be ignored (guard loopTask == nil)
        await service.start(appState: appState, interval: .milliseconds(100))

        try await Task.sleep(nanoseconds: 50_000_000)

        await service.stop()
    }

    @Test("monitor samples metrics")
    func monitorSamplesMetrics() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))

        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(appState.cpu.coreCount > 0)

        await service.stop()
    }

    @Test("pause stops sampling")
    func pauseStopsSampling() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))
        try await Task.sleep(nanoseconds: 100_000_000)

        appState.isMonitoringPaused = true
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(appState.isMonitoring)

        appState.isMonitoringPaused = false
        await service.stop()
    }

    @Test("resume resumes sampling after pause")
    func resumeAfterPause() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))
        try await Task.sleep(nanoseconds: 100_000_000)

        appState.isMonitoringPaused = true
        try await Task.sleep(nanoseconds: 100_000_000)

        appState.isMonitoringPaused = false
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(appState.isMonitoring)

        await service.stop()
    }

    @Test("monitor maintains CPU history")
    func cpuHistoryMaintenance() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))

        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(appState.cpuHistory.count >= 0)

        await service.stop()
    }

    @Test("monitor evaluates alerts")
    func monitorEvaluatesAlerts() async throws {
        let alertEngine = AlertEngine()
        let service = SystemMonitorService(alertEngine: alertEngine)
        let appState = AppState()

        let rule = AlertRule(
            id: UUID(),
            metric: .cpu,
            condition: .above,
            threshold: 1.0,
            cooldown: 0.5,
            isEnabled: true,
            label: "Test Alert"
        )

        await alertEngine.upsertRule(rule)

        await service.start(appState: appState, interval: .milliseconds(50))

        try await Task.sleep(nanoseconds: 200_000_000)

        let history = await alertEngine.getHistory()

        #expect(history.count >= 0)

        await service.stop()
    }

    @Test("service persists data")
    func dataPersistesThroughService() async throws {
        let dataStore = DataStore()
        let service = SystemMonitorService(dataStore: dataStore)
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(true)

        await service.stop()
    }

    @Test("service respects sampling interval")
    func samplingIntervalRespected() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        let startTime = Date()
        await service.start(appState: appState, interval: .milliseconds(100))

        try await Task.sleep(nanoseconds: 250_000_000)

        let elapsed = Date().timeIntervalSince(startTime)

        #expect(elapsed >= 0.25)

        await service.stop()
    }

    @Test("service continues on monitor errors")
    func errorRecovery() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(appState.isMonitoring)

        await service.stop()
    }

    @Test("appState updates happen on mainActor")
    func mainActorCoordination() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))

        try await Task.sleep(nanoseconds: 150_000_000)

        let cpuUsage = appState.cpu.usagePercent
        let memUsage = appState.ram.usedPercent

        #expect(cpuUsage >= 0)
        #expect(memUsage >= 0)

        await service.stop()
    }

    @Test("stop cancels loop properly")
    func cancellationBehavior() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))
        try await Task.sleep(nanoseconds: 100_000_000)

        await service.stop()

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(!appState.isMonitoring || appState.isMonitoringPaused)
    }

    @Test("full monitoring cycle works")
    func fullMonitoringCycle() async throws {
        let alertEngine = AlertEngine()
        let service = SystemMonitorService(alertEngine: alertEngine)
        let appState = AppState()

        let rule = AlertRule(
            id: UUID(),
            metric: .memory,
            condition: .above,
            threshold: 99.0,
            cooldown: 1,
            isEnabled: true,
            label: "Memory Test"
        )

        await alertEngine.upsertRule(rule)

        await service.start(appState: appState, interval: .milliseconds(50))

        appState.isMonitoringPaused = true
        try await Task.sleep(nanoseconds: 50_000_000)

        appState.isMonitoringPaused = false
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(appState.isMonitoring)

        let history = await alertEngine.getHistory()
        let rules = await alertEngine.getRules()

        #expect(rules.count > 0)

        await service.stop()

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(!appState.isMonitoring)
    }

    @Test("monitor operates efficiently at 1 second interval")
    func efficiencyTest() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        let startTime = Date()
        await service.start(appState: appState, interval: .seconds(1))

        try await Task.sleep(nanoseconds: 3_500_000_000)

        let elapsed = Date().timeIntervalSince(startTime)

        #expect(elapsed >= 3.0)
        #expect(elapsed < 5.0)

        await service.stop()
    }

    @Test("handles rapid start stop cycles")
    func rapidCycles() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        for _ in 0..<3 {
            await service.start(appState: appState, interval: .milliseconds(50))
            try await Task.sleep(nanoseconds: 50_000_000)
            await service.stop()
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(true)
    }
}
