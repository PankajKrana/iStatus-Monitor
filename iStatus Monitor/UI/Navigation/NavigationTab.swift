import SwiftUI

enum NavigationTab: String, CaseIterable, Identifiable {
    case dashboard
    case cpu
    case memory
    case network
    case gpu
    case thermal
    case battery
    case alerts
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .gpu: "GPU"
        case .thermal: "Thermal"
        case .battery: "Battery"
        case .alerts: "Alerts"
        case .history: "History"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .gpu: "bolt.triangle"
        case .thermal: "thermometer.sun.fill"
        case .battery: "battery.100"
        case .alerts: "bell.badge"
        case .history: "clock.arrow.circlepath"
        }
    }

    var keyboardShortcut: KeyboardShortcut? {
        switch self {
        case .dashboard: KeyboardShortcut("1", modifiers: .command)
        case .cpu: KeyboardShortcut("2", modifiers: .command)
        case .memory: KeyboardShortcut("3", modifiers: .command)
        case .network: KeyboardShortcut("4", modifiers: .command)
        case .gpu: KeyboardShortcut("5", modifiers: .command)
        case .thermal: KeyboardShortcut("6", modifiers: .command)
        case .battery: KeyboardShortcut("7", modifiers: .command)
        case .alerts: KeyboardShortcut("8", modifiers: .command)
        case .history: nil
        }
    }
}
