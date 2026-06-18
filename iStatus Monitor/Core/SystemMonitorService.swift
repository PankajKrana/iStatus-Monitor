import Darwin
import Foundation
import OSLog

actor SystemMonitorService {
    private let cpuMonitor: CPUMonitor
    private let memoryMonitor: MemoryMonitor
    private let batteryMonitor: BatteryMonitor
    private let networkMonitor: NetworkMonitor
    private let gpuMonitor: GPUMonitor
    private let thermalMonitor: ThermalMonitor
    private let diskMonitor: DiskMonitor
    private let dataStore: DataStore
    private let alertEngine: AlertEngine
    private let batteryAlertService: BatteryAlertService
    private let historyStore: HistoryStore?
    private let processMonitor: ProcessMonitor
    private let networkInsightsMonitor: NetworkInsightsMonitor

    /// Nominal CPU frequency, read once (static hardware fact). `nil` on Apple
    /// Silicon, where the sysctl is unavailable.
    private let cpuFrequencyGHz: Double?

    private var loopTask: Task<Void, Never>?

    /// Retained so the sampling interval can be changed at runtime (Settings →
    /// Update interval) by restarting the loop against the same state. Set on
    /// `start`, cleared on `stop`.
    private weak var activeAppState: AppState?
    private var activeInterval: Duration = .seconds(1)

    /// Incremented on every `start`. Each loop captures its generation and only
    /// writes the terminal `isMonitoring = false` if it is still the current
    /// generation — so a cancelled loop being torn down by `updateInterval`'s
    /// stop→start cannot stomp the freshly-started loop's `isMonitoring = true`.
    private var loopGeneration = 0

    init(
        cpuMonitor: CPUMonitor = CPUMonitor(),
        memoryMonitor: MemoryMonitor = MemoryMonitor(),
        batteryMonitor: BatteryMonitor = BatteryMonitor(),
        networkMonitor: NetworkMonitor = NetworkMonitor(),
        gpuMonitor: GPUMonitor = GPUMonitor(),
        thermalMonitor: ThermalMonitor = ThermalMonitor(),
        diskMonitor: DiskMonitor = DiskMonitor(),
        dataStore: DataStore = DataStore(),
        alertEngine: AlertEngine = AlertEngine(),
        batteryAlertService: BatteryAlertService = BatteryAlertService(),
        historyStore: HistoryStore? = nil,
        processMonitor: ProcessMonitor = ProcessMonitor(),
        networkInsightsMonitor: NetworkInsightsMonitor = NetworkInsightsMonitor()
    ) {
        self.cpuMonitor = cpuMonitor
        self.memoryMonitor = memoryMonitor
        self.batteryMonitor = batteryMonitor
        self.networkMonitor = networkMonitor
        self.gpuMonitor = gpuMonitor
        self.thermalMonitor = thermalMonitor
        self.diskMonitor = diskMonitor
        self.dataStore = dataStore
        self.alertEngine = alertEngine
        self.batteryAlertService = batteryAlertService
        self.historyStore = historyStore
        self.processMonitor = processMonitor
        self.networkInsightsMonitor = networkInsightsMonitor
        self.cpuFrequencyGHz = Self.readNominalCPUFrequencyGHz()
    }

    func start(appState: AppState, interval: Duration = .seconds(1)) {
        guard loopTask == nil else { return }

        // Retain for runtime interval changes (see `updateInterval`).
        activeAppState = appState
        activeInterval = interval
        loopGeneration += 1
        let generation = loopGeneration

        // Seconds per tick, derived from the actual loop interval so sustained
        // ("for Ns") alert rules measure wall-clock time correctly even when the
        // sampling interval differs from the 1s default (previously evaluate()
        // always assumed its 1s default, drifting if the interval changed).
        let intervalSeconds = Double(interval.components.seconds)
            + Double(interval.components.attoseconds) / 1_000_000_000_000_000_000

        Logger.monitoring.notice("Monitoring started (interval \(intervalSeconds, privacy: .public)s)")

        loopTask = Task {
            await MainActor.run { appState.isMonitoring = true }
            await alertEngine.requestAuthorizationIfNeeded()

            while !Task.isCancelled {
                let paused = await MainActor.run { appState.isMonitoringPaused }
                if paused {
                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        break
                    }
                    continue
                }

                let snapshot = await sampleAllMetrics()
                let cpuHistory = await cpuMonitor.history

                // Phase 2A insights ride the same tick — no new loop/timer. Gathered
                // concurrently with the metrics sample; applied to AppState separately
                // so they never enter the persisted SystemSnapshot.
                async let processSnapshot = processMonitor.latestSnapshot()
                async let networkInsights = networkInsightsMonitor.latest()
                let resolvedProcesses = await processSnapshot
                let resolvedInsights = await networkInsights

                await MainActor.run {
                    appState.apply(snapshot)
                    appState.applyInsights(
                        processes: resolvedProcesses,
                        network: resolvedInsights,
                        cpuFrequencyGHz: cpuFrequencyGHz
                    )
                    if let cpuSnapshot = snapshot.cpuSnapshot {
                        appState.applyCPU(snapshot: cpuSnapshot, history: cpuHistory)
                    }
                }

                await dataStore.persist(snapshot)
                await historyStore?.ingest(snapshot)
                await alertEngine.evaluate(snapshot, interval: intervalSeconds)
                await batteryAlertService.evaluate(snapshot.batterySnapshot)

                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
            }

            // Only the current generation may clear the flag. If a newer loop has
            // already started (e.g. via updateInterval's stop→start), it owns
            // `isMonitoring` and this stale loop must not flip it back to false.
            if await self.isCurrentGeneration(generation) {
                await MainActor.run { appState.isMonitoring = false }
            }
        }
    }

    /// Whether `generation` is still the most recently started loop. Isolated to
    /// the actor so the loop's terminal check reads a consistent value.
    private func isCurrentGeneration(_ generation: Int) -> Bool {
        generation == loopGeneration
    }

    func stop() {
        guard loopTask != nil else { return }
        loopTask?.cancel()
        loopTask = nil
        Logger.monitoring.notice("Monitoring stopped")
    }

    /// Change the sampling cadence at runtime (Settings → Update interval).
    /// Restarts the loop against the same `AppState` so the new interval takes
    /// effect immediately. No-op if monitoring was never started. The per-tick
    /// alert timing recomputes from the new interval inside `start`, so sustained
    /// ("for Ns") rules stay wall-clock-correct.
    func updateInterval(_ interval: Duration) {
        guard let appState = activeAppState else {
            // Not running yet — just remember it for the next start.
            activeInterval = interval
            return
        }
        guard interval != activeInterval else { return }
        Logger.monitoring.info("Sampling interval changed")
        stop()
        start(appState: appState, interval: interval)
    }

    /// Nominal CPU frequency in GHz via sysctl. Returns `nil` on Apple Silicon
    /// (`hw.cpufrequency*` is Intel-only); current per-core frequency on M-series
    /// would require private IOReport APIs and is out of scope.
    private static func readNominalCPUFrequencyGHz() -> Double? {
        for key in ["hw.cpufrequency_max", "hw.cpufrequency"] {
            var hz: UInt64 = 0
            var size = MemoryLayout<UInt64>.size
            if sysctlbyname(key, &hz, &size, nil, 0) == 0, hz > 0 {
                return Double(hz) / 1_000_000_000.0
            }
        }
        return nil
    }

    private func sampleAllMetrics() async -> SystemSnapshot {
        async let cpuSnapshot = cpuMonitor.latestSnapshot()
        async let memorySnapshot = memoryMonitor.latestSnapshot()
        async let batterySnapshot = batteryMonitor.latestSnapshot()
        async let networkSnapshot = networkMonitor.latestSnapshot()
        async let gpuSnapshot = gpuMonitor.latestSnapshot()
        async let thermalSnapshot = thermalMonitor.latestSnapshot()
        async let diskSnapshot = diskMonitor.latestSnapshot()

        let resolvedCPUSnapshot = await cpuSnapshot
        let resolvedMemorySnapshot = await memorySnapshot
        let resolvedBatterySnapshot = await batterySnapshot
        let resolvedNetworkSnapshot = await networkSnapshot
        let resolvedGPUSnapshot = await gpuSnapshot
        let resolvedThermalSnapshot = await thermalSnapshot
        let resolvedDiskSnapshot = await diskSnapshot

        let cpu: CPUMetrics
        if let resolvedCPUSnapshot {
            cpu = CPUMetrics(
                usagePercent: Double(resolvedCPUSnapshot.overallLoad * 100),
                coreCount: resolvedCPUSnapshot.perCoreUsage.count,
                temperatureCelsius: resolvedThermalSnapshot?.sensors.first(where: { $0.zone == .cpu })?.celsius
            )
        } else {
            cpu = .empty
        }

        let ram: MemoryMetrics
        if let resolvedMemorySnapshot {
            ram = MemoryMetrics(usedBytes: resolvedMemorySnapshot.usedBytes, totalBytes: resolvedMemorySnapshot.totalBytes)
        } else {
            ram = .empty
        }

        let battery: BatteryMetrics
        if let resolvedBatterySnapshot {
            battery = BatteryMetrics(
                levelPercent: resolvedBatterySnapshot.chargePercent,
                isCharging: resolvedBatterySnapshot.chargeState == .charging || resolvedBatterySnapshot.chargeState == .full,
                cycleCount: resolvedBatterySnapshot.cycleCount
            )
        } else {
            battery = .empty
        }

        let network: NetworkMetrics
        if let resolvedNetworkSnapshot {
            let primary = resolvedNetworkSnapshot.interfaces.first(where: { $0.isPrimary }) ?? resolvedNetworkSnapshot.interfaces.first
            let inBytes = resolvedNetworkSnapshot.interfaces.reduce(UInt64(0)) { $0 + $1.downloadBytesPerSecond }
            let outBytes = resolvedNetworkSnapshot.interfaces.reduce(UInt64(0)) { $0 + $1.uploadBytesPerSecond }
            network = NetworkMetrics(bytesInPerSecond: inBytes, bytesOutPerSecond: outBytes, primaryInterface: primary?.name ?? "")
        } else {
            network = .empty
        }

        let gpu: GPUMetrics
        if let resolvedGPUSnapshot, !resolvedGPUSnapshot.gpus.isEmpty {
            let avg = resolvedGPUSnapshot.gpus.map(\.utilizationPercent).reduce(0, +) / Double(resolvedGPUSnapshot.gpus.count)
            let temp = resolvedThermalSnapshot?.sensors.first(where: { $0.zone == .gpu })?.celsius
                ?? resolvedGPUSnapshot.gpus.compactMap(\.temperatureCelsius).first
            gpu = GPUMetrics(usagePercent: avg, temperatureCelsius: temp)
        } else {
            gpu = .empty
        }

        let disk: DiskMetrics
        if let resolvedDiskSnapshot {
            let primary = resolvedDiskSnapshot.primaryVolume
            disk = DiskMetrics(
                usedPercent: primary?.usedPercent ?? 0,
                usedBytes: primary?.usedBytes ?? 0,
                totalBytes: primary?.totalBytes ?? 0,
                readBytesPerSecond: resolvedDiskSnapshot.readBytesPerSecond,
                writeBytesPerSecond: resolvedDiskSnapshot.writeBytesPerSecond
            )
        } else {
            disk = .empty
        }

        return await SystemSnapshot(
            timestamp: Date(),
            cpu: cpu,
            cpuSnapshot: resolvedCPUSnapshot,
            ram: ram,
            memorySnapshot: resolvedMemorySnapshot,
            battery: battery,
            batterySnapshot: resolvedBatterySnapshot,
            network: network,
            networkSnapshot: resolvedNetworkSnapshot,
            gpu: gpu,
            gpuSnapshot: resolvedGPUSnapshot,
            disk: disk,
            diskSnapshot: resolvedDiskSnapshot,
            thermalSnapshot: resolvedThermalSnapshot
        )
    }
}
