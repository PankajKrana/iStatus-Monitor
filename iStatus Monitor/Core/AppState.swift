import Foundation
import Observation

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
    var thermalSnapshot: ThermalSnapshot?
    var lastUpdated: Date?
    var isMonitoring = false
    var isMonitoringPaused = false

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
        thermalSnapshot = snapshot.thermalSnapshot
        lastUpdated = snapshot.timestamp
    }

    func applyCPU(snapshot: CPUSnapshot, history: [CPUSnapshot]) {
        cpuSnapshot = snapshot
        cpuHistory = history
    }
}
