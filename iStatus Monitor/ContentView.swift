import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let cpuSnapshot = appState.cpuSnapshot {
                    CPUView(snapshot: cpuSnapshot)
                } else {
                    MetricRowView(title: "CPU", value: String(format: "%.0f%%", appState.cpu.usagePercent), tint: AppTheme.cpuColor)
                    UsageBarView(value: appState.cpu.usagePercent, tint: AppTheme.cpuColor)
                }

                if let memorySnapshot = appState.memorySnapshot {
                    MemoryView(snapshot: memorySnapshot)
                } else {
                    MetricRowView(title: "RAM", value: String(format: "%.0f%%", appState.ram.usedPercent), tint: AppTheme.ramColor)
                    UsageBarView(value: appState.ram.usedPercent, tint: AppTheme.ramColor)
                }

                if let batterySnapshot = appState.batterySnapshot {
                    BatteryView(snapshot: batterySnapshot)
                } else {
                    Text("Battery not available on this Mac")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }

                if let networkSnapshot = appState.networkSnapshot {
                    NetworkView(snapshot: networkSnapshot)
                } else {
                    MetricRowView(
                        title: "Network",
                        value: "↓ \(formatBytes(appState.network.bytesInPerSecond))/s ↑ \(formatBytes(appState.network.bytesOutPerSecond))/s",
                        tint: AppTheme.networkColor
                    )
                }

                MetricRowView(title: "GPU", value: String(format: "%.0f%%", appState.gpu.usagePercent), tint: AppTheme.gpuColor)
                UsageBarView(value: appState.gpu.usagePercent, tint: AppTheme.gpuColor)

                if let lastUpdated = appState.lastUpdated {
                    Text("Updated: \(lastUpdated.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(AppTheme.panelPadding)
        }
        .frame(minWidth: 620, minHeight: 760)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

#Preview {
    ContentView(appState: AppState())
}
