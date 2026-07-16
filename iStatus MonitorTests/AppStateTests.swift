import Foundation
import Testing
@testable import iStatus_Monitor

/// Coverage for `AppState.apply(_:)` — the single point where a `SystemSnapshot`
/// is fanned out into the live `*Metrics` values and the rich `*Snapshot`
/// references every view reads. These are deterministic (no hardware) and assert
/// that each domain is mapped to the right field and that the volatile snapshot
/// references are kept in sync with the coarse metrics.
@MainActor
struct AppStateTests {

    // MARK: - Fixtures

    /// A fully-populated snapshot using distinct, recognizable values per field so
    /// the mapping assertions below are meaningful.
    private func fullSnapshot() -> SystemSnapshot {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let cpuSnapshot = CPUSnapshot(
            timestamp: timestamp,
            perCoreUsage: [CoreUsage(coreIndex: 0, user: 0.5, system: 0.3, idle: 0.1, nice: 0.1)],
            overallLoad: 0.9,
            loadAverage: LoadAverage(one: 1, five: 2, fifteen: 3)
        )

        let memorySnapshot = MemorySnapshot(
            timestamp: timestamp,
            totalBytes: 16_000_000_000,
            usedBytes: 4_000_000_000,
            wiredBytes: 1_000,
            appBytes: 2_000,
            compressedBytes: 3_000,
            cachedBytes: 4_000,
            freeBytes: 12_000_000_000,
            swapUsedBytes: 0,
            swapTotalBytes: 0,
            pressure: .normal
        )

        let batterySnapshot = BatterySnapshot(
            timestamp: timestamp,
            currentCapacitymAh: 4000,
            designCapacitymAh: 5000,
            healthPercent: 90,
            cycleCount: 50,
            chargeState: .charging,
            chargePercent: 80,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: 30,
            voltageMillivolts: 12000,
            amperageMilliamps: 1000,
            watts: 12,
            temperatureCelsius: 31,
            temperatureFahrenheit: 87.8,
            serialNumber: "SN-1",
            chargeHistory24h: [],
            healthHistory: []
        )

        let networkSnapshot = NetworkSnapshot(
            timestamp: timestamp,
            interfaces: [InterfaceStats(
                name: "en0",
                displayName: "Wi-Fi",
                type: .wifi,
                downloadBytesPerSecond: 1000,
                uploadBytesPerSecond: 500,
                totalBytesReceived: 10_000,
                totalBytesSent: 5_000,
                ipv4Address: "192.168.1.2",
                ipv6Address: nil,
                isConnected: true,
                isPrimary: true
            )],
            connectivitySatisfied: true,
            totalDownloadSinceLaunch: 10_000,
            totalUploadSinceLaunch: 5_000,
            history60s: []
        )

        let gpuSnapshot = GPUSnapshot(
            timestamp: timestamp,
            gpus: [GPUStats(
                id: "gpu0",
                name: "Apple M-series",
                vendor: "Apple",
                utilizationPercent: 25,
                vramTotalMB: 8_000,
                vramUsedMB: 2_000,
                temperatureCelsius: 60,
                metalDeviceName: "Metal",
                isLowPower: false,
                isRemovable: false,
                recommendedMaxWorkingSetSize: 4_000,
                isIntegrated: true
            )],
            displays: []
        )

        let diskSnapshot = DiskSnapshot(
            timestamp: timestamp,
            volumes: [DiskVolume(
                name: "Macintosh HD",
                mountPoint: "/",
                totalBytes: 1_000_000,
                freeBytes: 500_000,
                isRemovable: false,
                isInternal: true
            )],
            readBytesPerSecond: 10,
            writeBytesPerSecond: 20,
            history60s: []
        )

        let thermalSnapshot = ThermalSnapshot(
            timestamp: timestamp,
            fans: [FanReading(index: 0, rpm: 1200, minRPM: 0, maxRPM: 6000, percentOfMax: 0.2)],
            sensors: [ThermalSensor(key: "cpu", name: "CPU", celsius: 70, fahrenheit: 158, zone: .cpu)],
            thermalState: .nominal
        )

        return SystemSnapshot(
            timestamp: timestamp,
            cpu: CPUMetrics(usagePercent: 55.5, coreCount: 8, temperatureCelsius: 70),
            cpuSnapshot: cpuSnapshot,
            ram: MemoryMetrics(usedBytes: 4_000_000_000, totalBytes: 16_000_000_000),
            memorySnapshot: memorySnapshot,
            battery: BatteryMetrics(levelPercent: 80, isCharging: true, cycleCount: 50),
            batterySnapshot: batterySnapshot,
            network: NetworkMetrics(bytesInPerSecond: 1000, bytesOutPerSecond: 500, primaryInterface: "en0"),
            networkSnapshot: networkSnapshot,
            gpu: GPUMetrics(usagePercent: 25, temperatureCelsius: 60),
            gpuSnapshot: gpuSnapshot,
            disk: DiskMetrics(usedPercent: 50, usedBytes: 50_000, totalBytes: 100_000, readBytesPerSecond: 10, writeBytesPerSecond: 20),
            diskSnapshot: diskSnapshot,
            thermalSnapshot: thermalSnapshot
        )
    }

    // MARK: - Mapping

    @Test("apply maps every domain from a full SystemSnapshot")
    func applyMapsFullSnapshot() {
        let snapshot = fullSnapshot()
        let appState = AppState()
        appState.apply(snapshot)

        // Coarse metrics
        #expect(appState.cpu.usagePercent == 55.5)
        #expect(appState.cpu.coreCount == 8)
        #expect(appState.cpu.temperatureCelsius == 70)
        #expect(appState.ram.usedBytes == 4_000_000_000)
        #expect(appState.ram.totalBytes == 16_000_000_000)
        #expect(appState.ram.usedPercent == 25)
        #expect(appState.battery.levelPercent == 80)
        #expect(appState.battery.isCharging)
        #expect(appState.battery.cycleCount == 50)
        #expect(appState.network.bytesInPerSecond == 1000)
        #expect(appState.network.bytesOutPerSecond == 500)
        #expect(appState.network.primaryInterface == "en0")
        #expect(appState.gpu.usagePercent == 25)
        #expect(appState.gpu.temperatureCelsius == 60)
        #expect(appState.disk.usedPercent == 50)
        #expect(appState.disk.usedBytes == 50_000)
        #expect(appState.disk.totalBytes == 100_000)
        #expect(appState.disk.readBytesPerSecond == 10)
        #expect(appState.disk.writeBytesPerSecond == 20)

        // Rich snapshot references are carried through verbatim
        #expect(appState.cpuSnapshot == snapshot.cpuSnapshot)
        #expect(appState.memorySnapshot == snapshot.memorySnapshot)
        #expect(appState.batterySnapshot == snapshot.batterySnapshot)
        #expect(appState.networkSnapshot == snapshot.networkSnapshot)
        #expect(appState.gpuSnapshot == snapshot.gpuSnapshot)
        #expect(appState.diskSnapshot == snapshot.diskSnapshot)
        #expect(appState.thermalSnapshot == snapshot.thermalSnapshot)

        #expect(appState.lastUpdated == snapshot.timestamp)
    }

    @Test("apply feeds the cpu value into menu-bar sparkline history")
    func applyRecordsMenuBarHistory() {
        let snapshot = fullSnapshot()
        let appState = AppState()
        appState.apply(snapshot)

        let cpuHistory = appState.menuBarHistory.values(for: "cpu")
        #expect(!cpuHistory.isEmpty)
        #expect(cpuHistory.last == 55.5)
    }

    @Test("apply clears rich snapshot references when snapshots are nil")
    func applyWithNilSnapshots() {
        let snapshot = SystemSnapshot(
            timestamp: Date(timeIntervalSince1970: 123),
            cpu: CPUMetrics(usagePercent: 10, coreCount: 4, temperatureCelsius: nil),
            cpuSnapshot: nil,
            ram: MemoryMetrics(usedBytes: 1, totalBytes: 2),
            memorySnapshot: nil,
            battery: BatteryMetrics(levelPercent: 50, isCharging: false, cycleCount: nil),
            batterySnapshot: nil,
            network: NetworkMetrics(bytesInPerSecond: 0, bytesOutPerSecond: 0, primaryInterface: ""),
            networkSnapshot: nil,
            gpu: GPUMetrics(usagePercent: 0, temperatureCelsius: nil),
            gpuSnapshot: nil,
            disk: DiskMetrics(usedPercent: 0, usedBytes: 0, totalBytes: 0, readBytesPerSecond: 0, writeBytesPerSecond: 0),
            diskSnapshot: nil,
            thermalSnapshot: nil
        )

        let appState = AppState()
        appState.apply(snapshot)

        // Coarse metrics still mapped even with no rich snapshot.
        #expect(appState.cpu.usagePercent == 10)
        #expect(appState.cpu.coreCount == 4)
        #expect(appState.battery.levelPercent == 50)
        // Volatile references are reset to nil.
        #expect(appState.cpuSnapshot == nil)
        #expect(appState.memorySnapshot == nil)
        #expect(appState.batterySnapshot == nil)
        #expect(appState.networkSnapshot == nil)
        #expect(appState.gpuSnapshot == nil)
        #expect(appState.diskSnapshot == nil)
        #expect(appState.thermalSnapshot == nil)
    }

    @Test("apply overwrites previously applied values")
    func applyOverwritesPrevious() {
        let first = SystemSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            cpu: CPUMetrics(usagePercent: 10, coreCount: 2, temperatureCelsius: nil),
            cpuSnapshot: nil,
            ram: MemoryMetrics(usedBytes: 1, totalBytes: 2),
            memorySnapshot: nil,
            battery: BatteryMetrics(levelPercent: 10, isCharging: false, cycleCount: nil),
            batterySnapshot: nil,
            network: NetworkMetrics(bytesInPerSecond: 1, bytesOutPerSecond: 1, primaryInterface: "a"),
            networkSnapshot: nil,
            gpu: GPUMetrics(usagePercent: 1, temperatureCelsius: nil),
            gpuSnapshot: nil,
            disk: DiskMetrics(usedPercent: 1, usedBytes: 1, totalBytes: 1, readBytesPerSecond: 1, writeBytesPerSecond: 1),
            diskSnapshot: nil,
            thermalSnapshot: nil
        )

        let second = SystemSnapshot(
            timestamp: Date(timeIntervalSince1970: 2),
            cpu: CPUMetrics(usagePercent: 99, coreCount: 8, temperatureCelsius: nil),
            cpuSnapshot: nil,
            ram: MemoryMetrics(usedBytes: 5, totalBytes: 10),
            memorySnapshot: nil,
            battery: BatteryMetrics(levelPercent: 90, isCharging: true, cycleCount: nil),
            batterySnapshot: nil,
            network: NetworkMetrics(bytesInPerSecond: 9, bytesOutPerSecond: 9, primaryInterface: "b"),
            networkSnapshot: nil,
            gpu: GPUMetrics(usagePercent: 9, temperatureCelsius: nil),
            gpuSnapshot: nil,
            disk: DiskMetrics(usedPercent: 9, usedBytes: 9, totalBytes: 10, readBytesPerSecond: 9, writeBytesPerSecond: 9),
            diskSnapshot: nil,
            thermalSnapshot: nil
        )

        let appState = AppState()
        appState.apply(first)
        #expect(appState.cpu.usagePercent == 10)
        #expect(appState.battery.levelPercent == 10)
        #expect(!appState.battery.isCharging)

        appState.apply(second)
        #expect(appState.cpu.usagePercent == 99)
        #expect(appState.cpu.coreCount == 8)
        #expect(appState.battery.levelPercent == 90)
        #expect(appState.battery.isCharging)
        #expect(appState.network.primaryInterface == "b")
        #expect(appState.lastUpdated == second.timestamp)
    }
}
