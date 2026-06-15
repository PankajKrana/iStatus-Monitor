import Foundation
import Observation
import Darwin.POSIX

/// The single source of truth for **live metric data**, fed by
/// `SystemMonitorService` on each tick and read by every UI surface.
///
/// Each domain is held in two complementary forms, by design:
/// - a coarse `*Metrics` value (e.g. `cpu`) for at-a-glance reads (menu bar,
///   compact gauges) — always present, defaulting to `.empty`; and
/// - a rich optional `*Snapshot` (e.g. `cpuSnapshot`) carrying the full detail
///   for the dashboard, `nil` until the first sample (or where the hardware has
///   no data, e.g. battery on a desktop).
///
/// Because this is `@Observable`, SwiftUI tracks reads per property: a view that
/// only reads `cpu` is re-rendered when `cpu` changes, not when `battery` does.
@MainActor
@Observable
final class AppState {

    // MARK: Live metrics (persisted via SystemSnapshot)

    var cpu: CPUMetrics = .empty
    var cpuSnapshot: CPUSnapshot?
    var cpuHistory: [CPUSnapshot] = []
    var ram: MemoryMetrics = .empty
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

    // MARK: Monitoring lifecycle

    var isMonitoring = false
    var isMonitoringPaused = false

    // MARK: Phase 2A insights (volatile — populated via `applyInsights`, never persisted)

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
