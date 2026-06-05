import AppKit
import SwiftUI

/// Integration layer that converts AppState metrics into MenuBarDisplayValue items
/// and manages the visual representation in the menu bar using SF Symbols
final class MenuBarIconIntegration {
    private let appState: AppState
    private let settings: MenuBarSettings
    
    init(appState: AppState, settings: MenuBarSettings) {
        self.appState = appState
        self.settings = settings
    }

    /// Converts current AppState metrics to displayable menu bar values
    func getDisplayValues() -> [MenuBarDisplayValue] {
        var values: [MenuBarDisplayValue] = []
        
        if settings.showCPU {
            values.append(
                MenuBarDisplayValue(
                    metric: .cpu,
                    percentage: appState.cpu.usagePercent,
                    label: "CPU",
                    secondaryValue: nil,
                    color: colorForMetric(.cpu, value: appState.cpu.usagePercent),
                    isWarning: appState.cpu.usagePercent > 75,
                    isCritical: appState.cpu.usagePercent > 90
                )
            )
        }
        
        if settings.showRAM {
            values.append(
                MenuBarDisplayValue(
                    metric: .memory,
                    percentage: appState.ram.usedPercent,
                    label: "RAM",
                    secondaryValue: nil,
                    color: colorForMetric(.memory, value: appState.ram.usedPercent),
                    isWarning: appState.ram.usedPercent > 80,
                    isCritical: appState.ram.usedPercent > 95
                )
            )
        }
        
        if settings.showGPU {
            values.append(
                MenuBarDisplayValue(
                    metric: .gpu,
                    percentage: appState.gpu.usagePercent,
                    label: "GPU",
                    secondaryValue: nil,
                    color: colorForMetric(.gpu, value: appState.gpu.usagePercent),
                    isWarning: appState.gpu.usagePercent > 75,
                    isCritical: appState.gpu.usagePercent > 90
                )
            )
        }
        
        if settings.showBattery, let battery = appState.batterySnapshot {
            values.append(
                MenuBarDisplayValue(
                    metric: .battery,
                    percentage: battery.chargePercent,
                    label: "Battery",
                    secondaryValue: batteryStatus(battery),
                    color: colorForBattery(battery.chargePercent),
                    isWarning: battery.chargePercent < 20,
                    isCritical: battery.chargePercent < 10
                )
            )
        }
        
        if settings.showNetwork, let network = appState.networkSnapshot {
            let totalThroughput = network.history60s.map { $0.uploadBytesPerSecond + $0.downloadBytesPerSecond }.max() ?? 0
            let latestThroughput = network.history60s.last.map { $0.uploadBytesPerSecond + $0.downloadBytesPerSecond } ?? 0
            values.append(
                MenuBarDisplayValue(
                    metric: .network,
                    percentage: min(100, Double(latestThroughput) / 1_000_000), // Normalize to 100% at 1MB/s
                    label: "Network",
                    secondaryValue: networkSpeed(uploadBps: network.history60s.last?.uploadBytesPerSecond ?? 0, downloadBps: network.history60s.last?.downloadBytesPerSecond ?? 0),
                    color: .blue,
                    isWarning: latestThroughput > 100_000_000, // > 100 MB/s
                    isCritical: false
                )
            )
        }
        
        if settings.showTemperature, let thermal = appState.thermalSnapshot {
            let maxTemp = thermal.sensors.map(\.celsius).max() ?? 0
            values.append(
                MenuBarDisplayValue(
                    metric: .temperature,
                    percentage: min(100, maxTemp / 100 * 100), // Normalize assuming max ~100°C
                    label: "Temperature",
                    secondaryValue: String(format: "%.1f°C", maxTemp),
                    color: colorForTemperature(maxTemp),
                    isWarning: maxTemp > 80,
                    isCritical: maxTemp > 95
                )
            )
        }
        
        return values
    }
    
    /// Generates SF Symbol name with dynamic variants for battery and temperature
    func getSymbolName(for metric: MenuBarMetricType, value: Double) -> String {
        switch metric {
        case .battery:
            let percent = value
            if percent <= 0 { return "battery.0" }
            if percent < 10 { return "battery.0" }
            if percent < 25 { return "battery.25" }
            if percent < 50 { return "battery.50" }
            if percent < 75 { return "battery.75" }
            return "battery.100"
            
        case .temperature:
            if value < 40 { return "thermometer.low" }
            if value < 60 { return "thermometer.mid" }
            return "thermometer.high"
            
        case .cpu:
            return "cpu"
        case .memory:
            return "memorychip"
        case .network:
            return "arrow.down.arrow.up"
        case .ssd:
            return "internaldrive.fill"
        case .gpu:
            return "display"
        }
    }
    
    // MARK: - Private Helpers
    
    private func colorForMetric(_ metric: MenuBarMetricType, value: Double) -> Color {
        switch metric {
        case .cpu:
            if value > 90 { return .red }
            if value > 75 { return .orange }
            return .blue
        case .memory:
            if value > 95 { return .red }
            if value > 80 { return .orange }
            return .blue
        case .gpu:
            if value > 90 { return .red }
            if value > 75 { return .orange }
            return .purple
        default:
            return .primary
        }
    }
    
    private func colorForBattery(_ percent: Double) -> Color {
        if percent < 10 { return .red }
        if percent < 20 { return .orange }
        return .green
    }
    
    private func colorForTemperature(_ celsius: Double) -> Color {
        if celsius > 95 { return .red }
        if celsius > 80 { return .orange }
        return .blue
    }
    
    private func batteryStatus(_ battery: BatterySnapshot) -> String? {
        switch battery.chargeState {
        case .charging:
            if let timeToFull = battery.timeToFullMinutes {
                return "⚡ \(timeToFull)m"
            }
            return "⚡ Charging"
        case .discharging:
            if let timeToEmpty = battery.timeToEmptyMinutes {
                return "🔋 \(timeToEmpty)m left"
            }
            return "🔋 Discharging"
        case .full, .ac:
            return "○ Full"
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
    
    private func networkSpeed(uploadBps: UInt64, downloadBps: UInt64) -> String? {
        let upload = formatNetworkSpeed(uploadBps)
        let download = formatNetworkSpeed(downloadBps)
        return "↓ \(download) ↑ \(upload)"
    }
    
    private func formatNetworkSpeed(_ bytesPerSecond: UInt64) -> String {
        let kilobytes = Double(bytesPerSecond) / 1024
        if kilobytes < 1024 {
            return String(format: "%.1f KB/s", kilobytes)
        }
        let megabytes = kilobytes / 1024
        return String(format: "%.1f MB/s", megabytes)
    }
}
