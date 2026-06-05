import AppKit
import SwiftUI

@MainActor
final class MenuBarManager {
    private let appState: AppState
    private let settings: MenuBarSettings

    private var statusItem: NSStatusItem?
    private var popover: MenuBarPopover?
    private var timer: Timer?

    private var cpuHistory: [Double] = []
    private var ramHistory: [Double] = []

    private var networkScale: Double = 1_000_000

    init(appState: AppState, settings: MenuBarSettings) {
        self.appState = appState
        self.settings = settings
    }

    func start() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(handleStatusItemClick)
            item.button?.sendAction(on: [.leftMouseUp])
            statusItem = item
        }

        if popover == nil {
            popover = MenuBarPopover(content: MenuBarDashboardView(appState: appState, settings: settings, manager: self))
        }

        updateStatusItem()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func openMainWindow() {
        settings.showDockIcon = true
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc
    private func handleStatusItemClick() {
        guard let button = statusItem?.button, let popover else { return }
        popover.update(content: MenuBarDashboardView(appState: appState, settings: settings, manager: self))
        popover.toggle(relativeTo: button)
    }

    private func tick() {
        if let popover, popover.popover.isShown {
            popover.update(content: MenuBarDashboardView(appState: appState, settings: settings, manager: self))
        }

        appendHistory()
        updateStatusItem()
    }

    private func appendHistory() {
        cpuHistory.append(appState.cpu.usagePercent)
        ramHistory.append(appState.ram.usedPercent)

        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
        if ramHistory.count > 60 { ramHistory.removeFirst(ramHistory.count - 60) }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let cpu = appState.cpu.usagePercent
        let ram = appState.ram.usedPercent
        let gpu = appState.gpu.usagePercent
        let network = Double(appState.network.bytesInPerSecond + appState.network.bytesOutPerSecond)
        networkScale = max(networkScale * 0.92, network, 250_000)
        let networkNormalized = min(100, (network / networkScale) * 100)

        // Build menu bar text based on enabled metrics
        var menuBarComponents: [String] = []

        if settings.showCPU {
            menuBarComponents.append(formatMetric(symbol: "🖥️", value: cpu, label: "CPU"))
        }
        if settings.showRAM {
            menuBarComponents.append(formatMetric(symbol: "🧠", value: ram, label: "RAM"))
        }
        if settings.showGPU {
            menuBarComponents.append(formatMetric(symbol: "📺", value: gpu, label: "GPU"))
        }
        if settings.showNetwork {
            let netLabel = String(format: "↓↑ %.0f%%", networkNormalized)
            menuBarComponents.append(netLabel)
        }

        switch settings.displayMode {
        case .miniChart:
            button.title = ""
            button.image = renderMiniChartImage(cpu: cpu, ram: ram, network: networkNormalized, gpu: gpu)
            button.toolTip = menuBarComponents.joined(separator: " • ")
        case .text:
            button.image = nil
            button.title = menuBarComponents.joined(separator: " | ")
            button.toolTip = nil
        }
    }

    private func formatMetric(symbol: String, value: Double, label: String) -> String {
        String(format: "%@ %.0f%%", symbol, value)
    }

    private func renderMiniChartImage(cpu: Double, ram: Double, network: Double, gpu: Double) -> NSImage {
        let width: CGFloat = 56
        let height: CGFloat = 18
        let bars: [Double] = [cpu, ram, network, gpu]
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemPurple]

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let barWidth: CGFloat = 8
        let spacing: CGFloat = 5

        for idx in 0 ..< bars.count {
            let x = CGFloat(idx) * (barWidth + spacing) + 2
            let normalized = max(0, min(1, bars[idx] / 100))
            let barHeight = max(2, normalized * 12)
            let y = (height - barHeight) / 2

            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            ctx.setFillColor(colors[idx].cgColor)
            ctx.fill(rect)

            if bars[idx] >= 85 {
                let dotRect = CGRect(x: x + barWidth / 2 - 1.6, y: height - 3.6, width: 3.2, height: 3.2)
                ctx.setFillColor(NSColor.systemRed.cgColor)
                ctx.fillEllipse(in: dotRect)
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    var compactCPUHistory: [Double] { cpuHistory }
    var compactRAMHistory: [Double] { ramHistory }
}

struct MenuBarDashboardView: View {
    @Bindable var appState: AppState
    @Bindable var settings: MenuBarSettings
    let manager: MenuBarManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iStatus Monitor")
                        .font(.headline)
                    Text(versionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    manager.openMainWindow()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }

            if settings.showCPU {
                row("CPU", String(format: "%.0f%%", appState.cpu.usagePercent), sparkline: manager.compactCPUHistory, color: .red)
            }
            if settings.showRAM {
                row("RAM", String(format: "%.0f%%", appState.ram.usedPercent), sparkline: manager.compactRAMHistory, color: .blue)
            }
            if settings.showNetwork {
                row(
                    "Network",
                    "↑ \(Int(appState.network.bytesOutPerSecond).toNetworkSpeedString())  ↓ \(Int(appState.network.bytesInPerSecond).toNetworkSpeedString())",
                    sparkline: appState.networkSnapshot?.history60s.map { Double($0.downloadBytesPerSecond + $0.uploadBytesPerSecond) } ?? [],
                    color: .green
                )
            }
            if settings.showBattery {
                row("Battery", batteryText, sparkline: appState.batterySnapshot?.chargeHistory24h.map(\.chargePercent) ?? [], color: .orange)
            }
            if settings.showTemperature {
                row("Temperature", temperatureText, sparkline: appState.thermalSnapshot?.sensors.map(\.celsius) ?? [], color: .pink)
            }
            if settings.showGPU {
                row("GPU", String(format: "%.0f%%", appState.gpu.usagePercent), sparkline: [appState.gpu.usagePercent], color: .purple)
            }

            Toggle("Pause monitoring", isOn: $appState.isMonitoringPaused)

            HStack {
                Button("Open Full Dashboard") {
                    manager.openMainWindow()
                }
                Spacer()
            }
        }
        .frame(width: 320)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        return "Version \(version)"
    }

    private var batteryText: String {
        guard let battery = appState.batterySnapshot else { return "N/A" }
        let time: String
        switch battery.chargeState {
        case .charging:
            time = battery.timeToFullMinutes.map { "\($0)m to full" } ?? "--"
        case .discharging:
            time = battery.timeToEmptyMinutes.map { "\($0)m left" } ?? "--"
        default:
            time = battery.chargeState.rawValue.capitalized
        }
        return String(format: "%.0f%% • %@", battery.chargePercent, time)
    }

    private var temperatureText: String {
        guard let maxTemp = appState.thermalSnapshot?.sensors.map(\.celsius).max() else { return "N/A" }
        return String(format: "%.1f°C", maxTemp)
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String, sparkline: [Double], color: Color) -> some View {
        HStack {
            Text(title)
                .frame(width: 90, alignment: .leading)
            SparklineView(values: sparkline, color: color)
                .frame(width: 110)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

struct MenuBarSettingsView: View {
    @Bindable var settings: MenuBarSettings

    var body: some View {
        Form {
            Picker("Menu Bar Display", selection: $settings.displayMode) {
                Text("Mini Chart").tag(MenuBarDisplayMode.miniChart)
                Text("Text").tag(MenuBarDisplayMode.text)
            }

            Toggle("Show CPU", isOn: $settings.showCPU)
            Toggle("Show RAM", isOn: $settings.showRAM)
            Toggle("Show Network", isOn: $settings.showNetwork)
            Toggle("Show Battery", isOn: $settings.showBattery)
            Toggle("Show Temperature", isOn: $settings.showTemperature)
            Toggle("Show GPU", isOn: $settings.showGPU)

            Divider()

            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            Toggle("Show Dock Icon", isOn: $settings.showDockIcon)
        }
        .padding(16)
        .frame(width: 420)
    }
}
