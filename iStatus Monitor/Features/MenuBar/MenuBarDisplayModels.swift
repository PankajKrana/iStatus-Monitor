import Foundation
import SwiftUI

// MARK: - Menu Bar Display Styles

enum MenuBarDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case iconPercentage = "icon_percentage"      // 🖥️ 25%
    case iconLabelPercentage = "icon_label_pct"  // 🖥️ CPU 25%
    case iconOnly = "icon_only"                  // 🖥️
    case compactIconValue = "compact_icon_val"   // 🖥️25%

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iconPercentage: "Icon + %" 
        case .iconLabelPercentage: "Icon + Label + %"
        case .iconOnly: "Icon Only"
        case .compactIconValue: "Compact Icon + Value"
        }
    }

    var description: String {
        switch self {
        case .iconPercentage: "Minimal design showing icon and percentage"
        case .iconLabelPercentage: "Full design with icon, label, and percentage"
        case .iconOnly: "Ultra-compact, icon only"
        case .compactIconValue: "Balanced compact format"
        }
    }
}

// MARK: - Metric Type for Menu Bar

enum MenuBarMetricType: String, Codable, CaseIterable, Identifiable {
    case cpu
    case memory
    case battery
    case network
    case ssd
    case temperature
    case gpu

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .battery: "Battery"
        case .network: "Network"
        case .ssd: "SSD"
        case .temperature: "Temperature"
        case .gpu: "GPU"
        }
    }

    var sfSymbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .battery: "battery.75"
        case .network: "arrow.down.arrow.up"
        case .ssd: "internaldrive.fill"
        case .temperature: "thermometer"
        case .gpu: "display"
        }
    }

    var shortLabel: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "RAM"
        case .battery: "Bat"
        case .network: "Net"
        case .ssd: "SSD"
        case .temperature: "Temp"
        case .gpu: "GPU"
        }
    }
}

// MARK: - SF Symbol Helper

struct MenuBarSymbol {
    let symbolName: String
    let isSystemSymbol: Bool

    init(_ name: String) {
        self.symbolName = name
        self.isSystemSymbol = true
    }

    func getBatterySymbol(for percentage: Double) -> String {
        switch percentage {
        case 0..<10: "battery.0"
        case 10..<25: "battery.25"
        case 25..<50: "battery.50"
        case 50..<75: "battery.75"
        case 75...100: "battery.100"
        default: "battery.75"
        }
    }

    func getNetworkSymbol(isActive: Bool = true) -> String {
        isActive ? "arrow.down.arrow.up" : "arrow.down.arrow.up.slash"
    }

    func getStorageSymbol(isFull: Bool = false) -> String {
        isFull ? "internaldrive.fill" : "internaldrive"
    }

    func getTemperatureSymbol(celsius: Double) -> String {
        switch celsius {
        case 0..<40: "thermometer.low"
        case 40..<60: "thermometer.mid"
        case 60...100: "thermometer.high"
        default: "thermometer"
        }
    }

    func getCPUSymbol(isActive: Bool = true) -> String {
        isActive ? "cpu" : "cpu"
    }
}

// MARK: - Menu Bar Metric Configuration

struct MenuBarMetricConfig: Codable, Identifiable {
    let id: String
    let metricType: MenuBarMetricType
    var isEnabled: Bool = true
    var displayStyle: MenuBarDisplayStyle = .iconPercentage
    var order: Int = 0

    var symbol: String {
        metricType.sfSymbol
    }

    var label: String {
        metricType.shortLabel
    }
}

// MARK: - Menu Bar Display Model

struct MenuBarDisplayValue {
    let metric: MenuBarMetricType
    let percentage: Double
    let label: String
    let secondaryValue: String?
    let color: Color
    let isWarning: Bool
    let isCritical: Bool

    var formattedValue: String {
        String(format: "%.0f%%", percentage)
    }

    var accessibilityLabel: String {
        if let secondary = secondaryValue {
            "\(label): \(formattedValue), \(secondary)"
        } else {
            "\(label): \(formattedValue)"
        }
    }
}

// MARK: - Menu Bar View State

@Observable
final class MenuBarViewState {
    var metrics: [MenuBarDisplayValue] = []
    var configurations: [MenuBarMetricConfig] = MenuBarMetricConfig.defaultConfigurations()
    var displayStyle: MenuBarDisplayStyle = .iconPercentage
    var hideWhenFullScreen: Bool = true
    var updateInterval: Double = 1.0
    var showLabels: Bool = true
    var compactMode: Bool = false
    var iconSize: CGFloat = 14
    var textSize: CGFloat = 10

    nonisolated static func defaultConfigurations() -> [MenuBarMetricConfig] {
        [
            MenuBarMetricConfig(id: "cpu", metricType: .cpu, isEnabled: true, order: 0),
            MenuBarMetricConfig(id: "memory", metricType: .memory, isEnabled: true, order: 1),
            MenuBarMetricConfig(id: "battery", metricType: .battery, isEnabled: false, order: 2),
            MenuBarMetricConfig(id: "network", metricType: .network, isEnabled: false, order: 3),
            MenuBarMetricConfig(id: "ssd", metricType: .ssd, isEnabled: false, order: 4),
            MenuBarMetricConfig(id: "temperature", metricType: .temperature, isEnabled: false, order: 5),
            MenuBarMetricConfig(id: "gpu", metricType: .gpu, isEnabled: false, order: 6),
        ]
    }

    func enabledConfigurations() -> [MenuBarMetricConfig] {
        configurations
            .filter { $0.isEnabled }
            .sorted { $0.order < $1.order }
    }

    func toggleMetric(_ metricType: MenuBarMetricType) {
        if let index = configurations.firstIndex(where: { $0.metricType == metricType }) {
            configurations[index].isEnabled.toggle()
        }
    }

    func updateMetricDisplay(for metric: MenuBarMetricType, with value: Double) {
        // Update logic to be implemented with actual metric updates
    }
}

// MARK: - Default Configurations

extension MenuBarMetricConfig {
    nonisolated static func defaultConfigurations() -> [MenuBarMetricConfig] {
        [
            MenuBarMetricConfig(id: "cpu", metricType: .cpu, isEnabled: true, order: 0),
            MenuBarMetricConfig(id: "memory", metricType: .memory, isEnabled: true, order: 1),
            MenuBarMetricConfig(id: "battery", metricType: .battery, isEnabled: false, order: 2),
            MenuBarMetricConfig(id: "network", metricType: .network, isEnabled: false, order: 3),
            MenuBarMetricConfig(id: "ssd", metricType: .ssd, isEnabled: false, order: 4),
            MenuBarMetricConfig(id: "temperature", metricType: .temperature, isEnabled: false, order: 5),
            MenuBarMetricConfig(id: "gpu", metricType: .gpu, isEnabled: false, order: 6),
        ]
    }
}
