import Foundation
import Observation
import Darwin.POSIX

@MainActor
@Observable
final class AppState {
    var cpu: CPUMetrics = .empty
    var cpuSnapshot: CPUSnapshot?
    var cpuHistory: [CPUSnapshot] = []
    var ram: RAMMetrics = .empty
    var memorySnapshot: MemorySnapshot?
    var battery: BatteryMetrics = .empty
    var batterySnapshot: BatterySnapshot?
    var network: NetworkMetrics = .empty
    var networkSnapshot: NetworkSnapshot?
    var gpu: GPUMetrics = .empty
    var gpuSnapshot: GPUSnapshot?
    var disk: DiskMetrics = .empty
    var diskSnapshot: DiskSnapshot?
    var thermalSnapshot: ThermalSnapshot?
    var lastUpdated: Date?
    var isMonitoring = false
    var isMonitoringPaused = false

    // Phase 2A insights — populated via `applyInsights`, never persisted.
    var processSnapshot: ProcessSnapshot?
    var networkInsights: NetworkInsights?
    var cpuFrequencyGHz: Double?

    func apply(_ snapshot: SystemSnapshot) {
        cpu = snapshot.cpu
        ram = snapshot.ram
        memorySnapshot = snapshot.memorySnapshot
        battery = snapshot.battery
        batterySnapshot = snapshot.batterySnapshot
        network = snapshot.network
        networkSnapshot = snapshot.networkSnapshot
        gpu = snapshot.gpu
        gpuSnapshot = snapshot.gpuSnapshot
        disk = snapshot.disk
        diskSnapshot = snapshot.diskSnapshot
        thermalSnapshot = snapshot.thermalSnapshot
        lastUpdated = snapshot.timestamp
    }

    func applyCPU(snapshot: CPUSnapshot, history: [CPUSnapshot]) {
        cpuSnapshot = snapshot
        cpuHistory = history
    }

    /// Apply Phase 2A insight data gathered on the same monitoring tick. Kept
    /// separate from `apply(_:)` so this volatile, popover-only data never enters
    /// the persisted `SystemSnapshot`. `cpuFrequencyGHz` is `nil` on Apple Silicon.
    func applyInsights(processes: ProcessSnapshot?, network: NetworkInsights?, cpuFrequencyGHz: Double?) {
        processSnapshot = processes
        networkInsights = network
        self.cpuFrequencyGHz = cpuFrequencyGHz
    }

    var systemUptime: TimeInterval? {
        ProcessInfo.processInfo.systemUptime
    }
}
