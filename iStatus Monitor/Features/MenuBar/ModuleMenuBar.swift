import AppKit
import SwiftUI

// MARK: - Module Menu Bar Extra

/// One independent menu bar item for a single widget (Module mode).
///
/// This is a `Scene`, declared once per built-in widget in `MenuBarExtraScene`.
/// SwiftUI's `@SceneBuilder` cannot `ForEach` a runtime array into scenes, so the
/// fixed catalogue is enumerated statically and each item is shown/hidden via the
/// `isInserted` binding.
///
/// Visibility is **derived, never authoritative**: the binding reflects
/// `presentationMode == .module && isEnabled(id)`, and its setter is intentionally
/// a no-op. Removing the item through macOS menu bar customization must not mutate
/// widget configuration — enabled state is owned solely by Settings. (Widget
/// availability and menu bar visibility stay separate concerns until a dedicated
/// visibility model exists.)
struct ModuleMenuBarExtra: Scene {
    let appState: AppState
    let widgetManager: WidgetManager
    let widgetId: String

    var body: some Scene {
        MenuBarExtra(isInserted: isInsertedBinding) {
            ModuleMenuBarPopover(appState: appState, widgetManager: widgetManager, widgetId: widgetId)
        } label: {
            ModuleMenuBarLabel(widgetManager: widgetManager, widgetId: widgetId)
        }
        .menuBarExtraStyle(.window)
    }

    /// Get reflects mode + enabled state; set is deliberately ignored so menu bar
    /// customization can't toggle a widget's configuration.
    private var isInsertedBinding: Binding<Bool> {
        Binding(
            get: { widgetManager.presentationMode == .module && widgetManager.isEnabled(widgetId) },
            set: { _ in /* visibility controlled only by Settings — no-op */ }
        )
    }
}

// MARK: - Module Label

/// A single widget's `[CPU 32%]` label. Reuses `MenuBarSegmentView` so a module
/// item renders identically to the same widget's compact-mode segment.
struct ModuleMenuBarLabel: View {
    let widgetManager: WidgetManager
    let widgetId: String

    var body: some View {
        if let segment = widgetManager.moduleSegment(for: widgetId) {
            MenuBarSegmentView(segment: segment)
        } else {
            // No data yet (e.g. battery on a desktop): keep the item clickable
            // with the widget's own glyph.
            let widget = widgetManager.registry.widget(for: widgetId)
            Image(systemName: widget?.sfSymbol ?? "gauge.with.dots.needle.33percent")
                .accessibilityLabel("\(widget?.name ?? "Metric"): collecting data")
        }
    }
}

// MARK: - Module Popover

/// A lean, width-constrained popover for one widget. Built from the snapshot
/// data already in `AppState` (Phase 1 shows only fields the pipeline provides;
/// frequency, top processes, public IP, and active connections arrive in Phase 2).
struct ModuleMenuBarPopover: View {
    let appState: AppState
    let widgetManager: WidgetManager
    let widgetId: String

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { appState.beginInsightViewing() }
        .onDisappear { appState.endInsightViewing() }
    }

    private var header: some View {
        let widget = widgetManager.registry.widget(for: widgetId)
        return HStack(spacing: 8) {
            Image(systemName: widget?.sfSymbol ?? "gauge.with.dots.needle.33percent")
                .foregroundStyle(.secondary)
            Text(widget?.name ?? widgetId)
                .font(.headline)
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch widgetId {
        case "cpu": cpuContent
        case "ram": ramContent
        case "gpu": gpuContent
        case "network": networkContent
        case "battery": batteryContent
        case "ssd": ssdContent
        case "thermal": thermalContent
        default: unavailable
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button("Open Dashboard") {
                openWindow(id: iStatus_MonitorApp.dashboardWindowID)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            HStack {
                SettingsLink {
                    Text("Settings…")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private var unavailable: some View {
        Text("Collecting metrics…")
            .foregroundStyle(.secondary)
            .font(.callout)
    }

    // MARK: Per-widget bodies

    @ViewBuilder
    private var cpuContent: some View {
        DetailRow(label: "Usage", value: MetricFormat.percent(appState.cpu.usagePercent))
        DetailRow(label: "Temperature",
                  value: appState.cpu.temperatureCelsius.map { String(format: "%.0f°C", $0) } ?? "—")
        if let ghz = appState.cpuFrequencyGHz {
            DetailRow(label: "Frequency", value: String(format: "%.2f GHz", ghz))
        }
        if let snapshot = appState.cpuSnapshot {
            DetailRow(label: "Load avg", value: String(format: "%.2f, %.2f, %.2f",
                                                        snapshot.loadAverage.one,
                                                        snapshot.loadAverage.five,
                                                        snapshot.loadAverage.fifteen))
            let active = snapshot.perCoreUsage.filter { $0.active > 0.05 }.count
            DetailRow(label: "Active cores", value: "\(active) of \(snapshot.perCoreUsage.count)")
        }
        if let processes = appState.processSnapshot, !processes.topByCPU.isEmpty {
            SectionLabel("Top Processes")
            ForEach(processes.topByCPU) { process in
                ProcessRow(name: process.name, value: String(format: "%.1f%%", process.cpuPercent))
            }
        }
    }

    @ViewBuilder
    private var ramContent: some View {
        if let memory = appState.memorySnapshot {
            DetailRow(label: "Total", value: MetricFormat.bytes(memory.totalBytes))
            DetailRow(label: "Used", value: "\(memory.usedString) (\(MetricFormat.percent(appState.ram.usedPercent)))")
            DetailRow(label: "Free", value: memory.freeString)
            DetailRow(label: "App", value: memory.appString)
            DetailRow(label: "Wired", value: memory.wiredString)
            DetailRow(label: "Compressed", value: memory.compressedString)
            DetailRow(label: "Cached", value: memory.cachedString)
            if memory.swapTotalBytes > 0 {
                DetailRow(label: "Swap", value: "\(memory.swapUsedString) / \(memory.swapTotalString)")
            }
            if let processes = appState.processSnapshot, !processes.topByMemory.isEmpty {
                SectionLabel("Top Processes")
                ForEach(processes.topByMemory) { process in
                    ProcessRow(name: process.name, value: MetricFormat.bytes(process.memoryBytes))
                }
            }
        } else {
            unavailable
        }
    }

    @ViewBuilder
    private var gpuContent: some View {
        if let snapshot = appState.gpuSnapshot, let gpu = snapshot.gpus.first {
            DetailRow(label: "Usage", value: MetricFormat.percent(appState.gpu.usagePercent))
            DetailRow(label: "Name", value: gpu.name)
            if let temp = gpu.temperatureCelsius {
                DetailRow(label: "Temperature", value: String(format: "%.0f°C", temp))
            }
            if let total = gpu.vramTotalMB, let used = gpu.vramUsedMB {
                DetailRow(label: "VRAM", value: "\(used) / \(total) MB")
            }
        } else {
            unavailable
        }
    }

    @ViewBuilder
    private var networkContent: some View {
        if let snapshot = appState.networkSnapshot {
            let primary = snapshot.interfaces.first(where: \.isPrimary) ?? snapshot.interfaces.first
            DetailRow(label: "Download", value: MetricFormat.speed(appState.network.bytesInPerSecond))
            DetailRow(label: "Upload", value: MetricFormat.speed(appState.network.bytesOutPerSecond))
            DetailRow(label: "Local IP", value: primary?.ipv4Address ?? "—")
            DetailRow(label: "Public IP", value: appState.networkInsights?.publicIP ?? "…")
            DetailRow(label: "Interface", value: primary?.displayName ?? primary?.name ?? "—")
            DetailRow(label: "Type", value: primary?.type.rawValue.capitalized ?? "—")

            if let insights = appState.networkInsights {
                DetailRow(label: "Active connections", value: "\(insights.connections.count)")

                if !insights.topProcesses.isEmpty {
                    SectionLabel("Top Network Processes")
                    ForEach(insights.topProcesses) { process in
                        ProcessRow(name: process.name, value: "\(process.connectionCount) conn")
                    }
                }

                if !insights.connections.isEmpty {
                    SectionLabel("Connections")
                    ForEach(Array(insights.connections.prefix(5))) { connection in
                        ProcessRow(name: connection.processName,
                                   value: "\(connection.remoteAddress):\(connection.remotePort)")
                    }
                }
            }
        } else {
            unavailable
        }
    }

    @ViewBuilder
    private var batteryContent: some View {
        if let battery = appState.batterySnapshot {
            DetailRow(label: "Percentage", value: MetricFormat.percent(battery.chargePercent))
            DetailRow(label: "Health", value: MetricFormat.percent(battery.healthPercent))
            DetailRow(label: "Cycle count", value: "\(battery.cycleCount)")
            DetailRow(label: "Time remaining", value: timeRemaining(battery))
            DetailRow(label: "Charging state", value: battery.chargeState.rawValue.capitalized)
            DetailRow(label: "Temperature", value: battery.temperatureCString)
        } else {
            Text("No battery on this Mac")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    @ViewBuilder
    private var ssdContent: some View {
        let volume = appState.diskSnapshot?.primaryVolume
        if let volume {
            DetailRow(label: "Total space", value: volume.totalString)
            DetailRow(label: "Used space", value: "\(volume.usedString) (\(MetricFormat.percent(volume.usedPercent)))")
            DetailRow(label: "Free space", value: volume.freeString)
        } else if appState.disk.totalBytes > 0 {
            DetailRow(label: "Total space", value: MetricFormat.bytes(appState.disk.totalBytes))
            DetailRow(label: "Used space", value: "\(MetricFormat.bytes(appState.disk.usedBytes)) (\(MetricFormat.percent(appState.disk.usedPercent)))")
            DetailRow(label: "Free space", value: MetricFormat.bytes(appState.disk.totalBytes - appState.disk.usedBytes))
        }
        DetailRow(label: "Read speed", value: MetricFormat.speed(appState.disk.readBytesPerSecond))
        DetailRow(label: "Write speed", value: MetricFormat.speed(appState.disk.writeBytesPerSecond))
    }

    @ViewBuilder
    private var thermalContent: some View {
        if let thermal = appState.thermalSnapshot {
            if let hottest = thermal.sensors.max(by: { $0.celsius < $1.celsius }) {
                DetailRow(label: "Hottest", value: "\(hottest.name) \(String(format: "%.0f°C", hottest.celsius))")
            }
            DetailRow(label: "State", value: thermalStateName(thermal.thermalState))
            if let fan = thermal.fans.first {
                DetailRow(label: "Fan", value: String(format: "%.0f RPM", fan.rpm))
            }
        } else {
            unavailable
        }
    }

    // MARK: Helpers

    private func timeRemaining(_ battery: BatterySnapshot) -> String {
        switch battery.chargeState {
        case .charging:
            return battery.timeToFullMinutes.map { "\($0)m to full" } ?? "Charging"
        case .discharging:
            return battery.timeToEmptyMinutes.map { "\($0)m left" } ?? "On battery"
        case .full: return "Full"
        case .ac: return "On AC"
        case .unknown: return "—"
        }
    }

    private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

// MARK: - Detail Row

/// One label/value line in a module popover.
private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

// MARK: - Section Label

/// A small section heading separating the base metrics from list sections
/// (top processes, connections).
private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

// MARK: - Process Row

/// A process/connection list row: truncating name on the left, value on the right.
private struct ProcessRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

// Metric strings are formatted via the shared `MetricFormat` helpers (see
// Core/MetricFormat.swift) so every surface renders values identically.
