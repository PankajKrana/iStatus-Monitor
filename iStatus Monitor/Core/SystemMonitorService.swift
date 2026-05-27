import Foundation

actor SystemMonitorService {
    private let cpuMonitor: CPUMonitor
    private let memoryMonitor: MemoryMonitor
    private let batteryMonitor: BatteryMonitor
    private let networkMonitor: NetworkMonitor
    private let gpuMonitor: GPUMonitor
    private let dataStore: DataStore
    private let alertEngine: AlertEngine
    private let batteryAlertService: BatteryAlertService

    private var loopTask: Task<Void, Never>?

    init(
        cpuMonitor: CPUMonitor = CPUMonitor(),
        memoryMonitor: MemoryMonitor = MemoryMonitor(),
        batteryMonitor: BatteryMonitor = BatteryMonitor(),
        networkMonitor: NetworkMonitor = NetworkMonitor(),
        gpuMonitor: GPUMonitor = GPUMonitor(),
        dataStore: DataStore = DataStore(),
        alertEngine: AlertEngine = AlertEngine(),
        batteryAlertService: BatteryAlertService = BatteryAlertService()
    ) {
        self.cpuMonitor = cpuMonitor
        self.memoryMonitor = memoryMonitor
        self.batteryMonitor = batteryMonitor
        self.networkMonitor = networkMonitor
        self.gpuMonitor = gpuMonitor
        self.dataStore = dataStore
        self.alertEngine = alertEngine
        self.batteryAlertService = batteryAlertService
    }

    func start(appState: AppState, interval: Duration = .seconds(1)) {
        guard loopTask == nil else { return }

        loopTask = Task {
            await MainActor.run { appState.isMonitoring = true }
            await alertEngine.requestAuthorization()

            while !Task.isCancelled {
                let snapshot = await sampleAllMetrics()
                let cpuHistory = await cpuMonitor.history

                await MainActor.run {
                    appState.apply(snapshot)
                    if let cpuSnapshot = snapshot.cpuSnapshot {
                        appState.applyCPU(snapshot: cpuSnapshot, history: cpuHistory)
                    }
                }

                await dataStore.persist(snapshot)
                await alertEngine.evaluate(snapshot)
                await batteryAlertService.evaluate(snapshot.batterySnapshot)

                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
            }

            await MainActor.run { appState.isMonitoring = false }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func sampleAllMetrics() async -> SystemSnapshot {
        async let cpuSnapshot = cpuMonitor.latestSnapshot()
        async let memorySnapshot = memoryMonitor.latestSnapshot()
        async let batterySnapshot = batteryMonitor.latestSnapshot()
        async let network = networkMonitor.read()
        async let gpu = gpuMonitor.read()

        let resolvedCPUSnapshot = await cpuSnapshot
        let resolvedMemorySnapshot = await memorySnapshot
        let resolvedBatterySnapshot = await batterySnapshot

        let cpu: CPUMetrics
        if let resolvedCPUSnapshot {
            cpu = CPUMetrics(
                usagePercent: Double(resolvedCPUSnapshot.overallLoad * 100),
                coreCount: resolvedCPUSnapshot.perCoreUsage.count,
                temperatureCelsius: nil
            )
        } else {
            cpu = .empty
        }

        let ram: RAMMetrics
        if let resolvedMemorySnapshot {
            ram = RAMMetrics(usedBytes: resolvedMemorySnapshot.usedBytes, totalBytes: resolvedMemorySnapshot.totalBytes)
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

        return await SystemSnapshot(
            timestamp: Date(),
            cpu: cpu,
            cpuSnapshot: resolvedCPUSnapshot,
            ram: ram,
            memorySnapshot: resolvedMemorySnapshot,
            battery: battery,
            batterySnapshot: resolvedBatterySnapshot,
            network: network,
            gpu: gpu
        )
    }
}
