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
    var network: NetworkMetrics = .empty
    var gpu: GPUMetrics = .empty
    var lastUpdated: Date?
    var isMonitoring = false

    func apply(_ snapshot: SystemSnapshot) {
        cpu = snapshot.cpu
        ram = snapshot.ram
        memorySnapshot = snapshot.memorySnapshot
        battery = snapshot.battery
        network = snapshot.network
        gpu = snapshot.gpu
        lastUpdated = snapshot.timestamp
    }

    func applyCPU(snapshot: CPUSnapshot, history: [CPUSnapshot]) {
        cpuSnapshot = snapshot
        cpuHistory = history
    }
}
