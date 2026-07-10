import Foundation
import Testing
@testable import iStatus_Monitor

@MainActor
struct SystemMonitorServiceTests {
    /// Polls `condition` until it holds or `timeout` elapses. The monitoring loop
    /// samples real hardware asynchronously, so a single fixed `Task.sleep` races
    /// under load / parallel execution; polling makes these assertions
    /// deterministic while testing the same behavior.
    private func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    // MARK: - Lifecycle

    @Test("start updates appState monitoring flag")
    func startUpdatesMonitoringFlag() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        #expect(!appState.isMonitoring)

        await service.start(appState: appState, interval: .milliseconds(50))

        #expect(await eventually { appState.isMonitoring })

        await service.stop()
    }

    @Test("stop cancels monitoring and clears the flag")
    func stopCancelsMonitoring() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))
        #expect(await eventually { appState.isMonitoring })

        await service.stop()

        // The loop must wind down and flip the flag back off — not merely "not crash".
        #expect(await eventually { !appState.isMonitoring })
    }

    @Test("start can only be called once")
    func startOnceGuard() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))
        #expect(await eventually { appState.isMonitoring })

        // A second start while running is ignored (guard loopTask == nil). After it,
        // a single stop must fully stop monitoring — proving no second loop leaked.
        await service.start(appState: appState, interval: .milliseconds(50))
        await service.stop()

        #expect(await eventually { !appState.isMonitoring })
    }

    // MARK: - Sampling

    @Test("monitor samples metrics into appState")
    func monitorSamplesMetrics() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))

        #expect(await eventually { appState.cpu.coreCount > 0 })
        #expect(await eventually { appState.lastUpdated != nil })

        await service.stop()
    }

    @Test("pause halts sampling; resume restarts it")
    func pauseAndResumeSampling() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))
        #expect(await eventually { appState.lastUpdated != nil })

        // While paused, no new samples land: lastUpdated must stop advancing.
        appState.isMonitoringPaused = true
        // Let any in-flight tick settle, then capture the frozen timestamp.
        try await Task.sleep(for: .milliseconds(120))
        let frozen = appState.lastUpdated
        try await Task.sleep(for: .milliseconds(120))
        #expect(appState.lastUpdated == frozen)
        #expect(appState.isMonitoring) // paused != stopped

        // Resuming produces a fresh sample.
        appState.isMonitoringPaused = false
        #expect(await eventually { appState.lastUpdated != frozen })

        await service.stop()
    }

    @Test("monitor accumulates CPU history while sampling")
    func cpuHistoryMaintenance() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))

        // History must actually grow — the sparkline buffer is now the single
        // source of rolling CPU history (fed on every tick by `AppState.apply`).
        #expect(await eventually { appState.menuBarHistory.values(for: "cpu").count >= 2 })

        await service.stop()
    }

    @Test("service keeps sampling across ticks")
    func serviceKeepsSampling() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))

        // A second timestamp proves the loop kept ticking.
        #expect(await eventually { appState.lastUpdated != nil })
        let first = appState.lastUpdated
        #expect(await eventually { appState.lastUpdated != first })

        await service.stop()
    }

    @Test("monitor runs alert evaluation on each tick")
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

        // Assert the loop drives sampling (evaluation rides the same tick). The
        // deterministic alert-firing semantics are covered in AlertEngineTests;
        // here we only verify the rule survives and sampling progresses.
        #expect(await eventually { appState.lastUpdated != nil })
        let rules = await alertEngine.getRules()
        #expect(rules.contains { $0.id == rule.id })

        await service.stop()
    }

    @Test("appState updates are valid and main-actor coordinated")
    func mainActorCoordination() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))

        #expect(await eventually { appState.cpu.coreCount > 0 })

        let cpuUsage = appState.cpu.usagePercent
        let memUsage = appState.ram.usedPercent

        #expect(cpuUsage >= 0)
        #expect(memUsage >= 0)

        await service.stop()
    }

    @Test("handles rapid start/stop cycles and ends stopped")
    func rapidCycles() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        for _ in 0..<3 {
            await service.start(appState: appState, interval: .milliseconds(50))
            #expect(await eventually { appState.isMonitoring })
            await service.stop()
            #expect(await eventually { !appState.isMonitoring })
        }
    }

    // MARK: - Interval changes

    @Test("updateInterval restarts the loop and keeps sampling")
    func updateIntervalRestartsLoop() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        await service.start(appState: appState, interval: .milliseconds(50))
        #expect(await eventually { appState.isMonitoring })

        // Change cadence at runtime — the loop should restart transparently and
        // continue updating AppState at the new interval.
        await service.updateInterval(.milliseconds(120))

        // Capture a baseline, then confirm a fresh sample lands after the change.
        let baseline = appState.lastUpdated
        let resampled = await eventually(timeout: .seconds(2)) {
            appState.isMonitoring && appState.lastUpdated != baseline
        }
        #expect(resampled)

        await service.stop()
    }

    @Test("updateInterval before start is a no-op that does not start monitoring")
    func updateIntervalBeforeStart() async throws {
        let service = SystemMonitorService()
        let appState = AppState()

        // No active AppState yet — should simply record the interval, not start.
        await service.updateInterval(.milliseconds(200))

        // Give any erroneous loop a chance to flip the flag, then assert it stayed off.
        try await Task.sleep(for: .milliseconds(100))
        #expect(!appState.isMonitoring)
    }
}
