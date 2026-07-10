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

    /// Rolling scalar history feeding the menu-bar sparklines. Mutated only in
    /// `apply(_:)` on the single sampling tick — no timer of its own.
    var menuBarHistory = MenuBarHistory()

    // MARK: Monitoring lifecycle

    var isMonitoring = false
    var isMonitoringPaused = false

    // MARK: Phase 2A insights (volatile — populated via `applyInsights`, never persisted)

    var processSnapshot: ProcessSnapshot?
    var networkInsights: NetworkInsights?
    var cpuFrequencyGHz: Double?

    // MARK: Insight sampling gate
    //
    // Process and network-insight enumeration walk every PID (and every socket fd)
    // on the tick — by far the heaviest samplers — yet they feed only the module
    // popovers. The monitoring loop skips them unless a popover that shows them is
    // open. Reference-counted because module mode can present several popovers at
    // once; sampling runs while the count is > 0.
    //
    // ponytail: fails safe — if a popover's onDisappear is missed (a known
    // MenuBarExtra quirk) the count just stays high and we sample as before; it
    // can never go negative or hide live data.
    private(set) var insightViewerCount = 0
    var wantsInsightSampling: Bool { insightViewerCount > 0 }
    func beginInsightViewing() { insightViewerCount += 1 }
    func endInsightViewing() { insightViewerCount = max(0, insightViewerCount - 1) }

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

        // Feed the sparkline history on the same tick — the only place live data
        // is written, so no extra timer or polling is introduced.
        menuBarHistory.record(cpu.usagePercent, for: "cpu")
        menuBarHistory.record(ram.totalBytes > 0 ? ram.usedPercent : nil, for: "ram")
        menuBarHistory.record(networkSnapshot != nil ? Double(network.bytesInPerSecond + network.bytesOutPerSecond) : nil, for: "network")
        menuBarHistory.record(disk.totalBytes > 0 ? disk.usedPercent : nil, for: "disk")
        menuBarHistory.record(gpuSnapshot != nil && !gpuSnapshot!.gpus.isEmpty ? gpu.usagePercent : nil, for: "gpu")
        menuBarHistory.record(batterySnapshot != nil ? battery.levelPercent : nil, for: "battery")
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
