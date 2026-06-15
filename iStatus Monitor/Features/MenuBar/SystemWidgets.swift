import Foundation

// Metric strings are formatted via the shared `MetricFormat` helpers so the
// menu bar, popovers, and dashboard all render values identically.

// MARK: - CPU

/// Overall CPU load. Reads `appState.cpu.usagePercent`. Always available.
nonisolated struct CPUWidget: MenuBarWidget {
    let id = "cpu"
    let name = "CPU"
    let sfSymbol = "cpu"
    let warningThreshold: Double = 70
    let criticalThreshold: Double = 90

    @MainActor func currentValue(from appState: AppState) -> Double? {
        appState.cpu.usagePercent
    }

    @MainActor func formattedValue(from appState: AppState) -> String {
        MetricFormat.percent(appState.cpu.usagePercent)
    }

    @MainActor func accessibilityLabel(from appState: AppState) -> String {
        "CPU: \(Int(appState.cpu.usagePercent.rounded())) percent"
    }
}

// MARK: - RAM

/// Memory pressure as used-percent. Reads `appState.ram.usedPercent`.
/// Unavailable until the first sample populates `totalBytes`.
nonisolated struct RAMWidget: MenuBarWidget {
    let id = "ram"
    let name = "RAM"
    let sfSymbol = "memorychip"
    let warningThreshold: Double = 75
    let criticalThreshold: Double = 90

    @MainActor func currentValue(from appState: AppState) -> Double? {
        guard appState.ram.totalBytes > 0 else { return nil }
        return appState.ram.usedPercent
    }

    @MainActor func formattedValue(from appState: AppState) -> String {
        guard let value = currentValue(from: appState) else { return "" }
        return MetricFormat.percent(value)
    }

    @MainActor func accessibilityLabel(from appState: AppState) -> String {
        guard let value = currentValue(from: appState) else { return "" }
        return "RAM: \(Int(value.rounded())) percent"
    }
}

// MARK: - GPU

/// GPU utilization. Reads `appState.gpu.usagePercent`, gated on a GPU snapshot
/// actually being present (Macs without a reportable GPU omit this widget).
nonisolated struct GPUWidget: MenuBarWidget {
    let id = "gpu"
    let name = "GPU"
    let sfSymbol = "display"
    let warningThreshold: Double = 75
    let criticalThreshold: Double = 90

    @MainActor func currentValue(from appState: AppState) -> Double? {
        guard let snapshot = appState.gpuSnapshot, !snapshot.gpus.isEmpty else { return nil }
        return appState.gpu.usagePercent
    }

    @MainActor func formattedValue(from appState: AppState) -> String {
        guard let value = currentValue(from: appState) else { return "" }
        return MetricFormat.percent(value)
    }

    @MainActor func accessibilityLabel(from appState: AppState) -> String {
        guard let value = currentValue(from: appState) else { return "" }
        return "GPU: \(Int(value.rounded())) percent"
    }
}

// MARK: - Network

/// Network throughput — informational only (never warns). Reads the per-second
/// rates from `appState.network`, gated on a network snapshot being present.
nonisolated struct NetworkWidget: MenuBarWidget {
    let id = "network"
    let name = "Network"
    let sfSymbol = "arrow.up.arrow.down"
    // Informational: thresholds are unreachable so the default severity is
    // always `.normal`; `severity(from:)` is also overridden for clarity.
    let warningThreshold: Double = .infinity
    let criticalThreshold: Double = .infinity

    @MainActor func currentValue(from appState: AppState) -> Double? {
        guard appState.networkSnapshot != nil else { return nil }
        return Double(appState.network.bytesInPerSecond + appState.network.bytesOutPerSecond)
    }

    @MainActor func formattedValue(from appState: AppState) -> String {
        guard appState.networkSnapshot != nil else { return "" }
        let down = MetricFormat.speed(appState.network.bytesInPerSecond)
        let up = MetricFormat.speed(appState.network.bytesOutPerSecond)
        return "↓ \(down) ↑ \(up)"
    }

    @MainActor func accessibilityLabel(from appState: AppState) -> String {
        guard appState.networkSnapshot != nil else { return "" }
        let down = MetricFormat.speed(appState.network.bytesInPerSecond)
        let up = MetricFormat.speed(appState.network.bytesOutPerSecond)
        return "Network: download \(down), upload \(up)"
    }

    @MainActor func severity(from appState: AppState) -> WidgetSeverity {
        .normal
    }
}

// MARK: - Battery

/// Battery charge. Reads `appState.batterySnapshot` (absent on desktops, so the
/// widget is omitted there). Severity is **inverted** — low charge is bad.
nonisolated struct BatteryWidget: MenuBarWidget {
    let id = "battery"
    let name = "Battery"
    let sfSymbol = "battery.75"
    let warningThreshold: Double = 20   // warn below this
    let criticalThreshold: Double = 10  // critical below this

    @MainActor func currentValue(from appState: AppState) -> Double? {
        appState.batterySnapshot?.chargePercent
    }

    @MainActor func formattedValue(from appState: AppState) -> String {
        guard let value = currentValue(from: appState) else { return "" }
        return MetricFormat.percent(value)
    }

    @MainActor func accessibilityLabel(from appState: AppState) -> String {
        guard let value = currentValue(from: appState) else { return "" }
        return "Battery: \(Int(value.rounded())) percent"
    }

    @MainActor func severity(from appState: AppState) -> WidgetSeverity {
        guard let value = currentValue(from: appState) else { return .normal }
        if value < criticalThreshold { return .critical }
        if value < warningThreshold { return .warning }
        return .normal
    }
}

// MARK: - SSD

/// Internal storage usage. Reads `appState.disk.usedPercent`, unavailable until
/// capacity has been sampled.
nonisolated struct SSDWidget: MenuBarWidget {
    let id = "ssd"
    let name = "SSD"
    let sfSymbol = "internaldrive.fill"
    let warningThreshold: Double = 80
    let criticalThreshold: Double = 90

    @MainActor func currentValue(from appState: AppState) -> Double? {
        guard appState.disk.totalBytes > 0 else { return nil }
        return appState.disk.usedPercent
    }

    @MainActor func formattedValue(from appState: AppState) -> String {
        guard let value = currentValue(from: appState) else { return "" }
        return MetricFormat.percent(value)
    }

    @MainActor func accessibilityLabel(from appState: AppState) -> String {
        guard let value = currentValue(from: appState) else { return "" }
        return "SSD: \(Int(value.rounded())) percent used"
    }
}

// MARK: - Thermal

/// Temperature. Displays the hottest sensor reading; severity is driven by the
/// system `ThermalState`, not the raw temperature. Reads
/// `appState.thermalSnapshot` (absent on hardware without sensors → omitted).
nonisolated struct ThermalWidget: MenuBarWidget {
    let id = "thermal"
    let name = "Temp"
    let sfSymbol = "thermometer"
    let warningThreshold: Double = 80
    let criticalThreshold: Double = 95

    @MainActor private func maxTemperature(from appState: AppState) -> Double? {
        guard let snapshot = appState.thermalSnapshot,
              let maxCelsius = snapshot.sensors.map(\.celsius).max() else { return nil }
        return maxCelsius
    }

    @MainActor func currentValue(from appState: AppState) -> Double? {
        maxTemperature(from: appState)
    }

    @MainActor func formattedValue(from appState: AppState) -> String {
        guard let celsius = maxTemperature(from: appState) else { return "" }
        return String(format: "%.0f°C", celsius)
    }

    @MainActor func accessibilityLabel(from appState: AppState) -> String {
        guard let celsius = maxTemperature(from: appState) else { return "" }
        return "Temperature: \(Int(celsius.rounded())) degrees Celsius"
    }

    @MainActor func severity(from appState: AppState) -> WidgetSeverity {
        guard let thermalState = appState.thermalSnapshot?.thermalState else { return .normal }
        switch thermalState {
        case .nominal: return .normal
        case .fair: return .warning
        case .serious, .critical: return .critical
        @unknown default: return .normal
        }
    }
}

// MARK: - Built-in Catalogue

extension WidgetRegistry {
    /// The seven built-in widgets, in their default display order. Used by the
    /// composition root to populate the registry.
    @MainActor
    static func builtInWidgets() -> [any MenuBarWidget] {
        [
            CPUWidget(),
            RAMWidget(),
            GPUWidget(),
            NetworkWidget(),
            BatteryWidget(),
            SSDWidget(),
            ThermalWidget(),
        ]
    }
}
