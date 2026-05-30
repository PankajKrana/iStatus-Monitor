import Foundation
import SwiftUI

struct DashboardView: View {
    @Bindable var appState: AppState
    @Bindable var alertsStore: AlertsStore
    let onNavigate: (NavigationTab) -> Void

    @State private var systemInfo: SystemInfo = .empty
    @State private var gradientAngle: Double = 0

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                systemBanner

                LazyVGrid(columns: columns, spacing: 16) {
                    MetricSummaryCard(
                        title: "CPU",
                        value: String(format: "%.1f%%", appState.cpu.usagePercent),
                        icon: "cpu",
                        tint: AppTheme.cpuColor,
                        sparkline: appState.cpuHistory.map { Double($0.overallLoad) * 100 },
                        status: cpuStatus,
                        gradientAngle: gradientAngle
                    ) {
                        onNavigate(.cpu)
                    }

                    MetricSummaryCard(
                        title: "Memory",
                        value: String(format: "%.1f%%", appState.ram.usedPercent),
                        icon: "memorychip",
                        tint: AppTheme.ramColor,
                        sparkline: [appState.memorySnapshot?.usedRatio].compactMap { $0 }.map { Double($0) * 100 },
                        status: memoryStatus,
                        gradientAngle: gradientAngle
                    ) {
                        onNavigate(.memory)
                    }

                    MetricSummaryCard(
                        title: "Network",
                        value: "↓ \(formatBytes(appState.network.bytesInPerSecond))/s",
                        icon: "network",
                        tint: AppTheme.networkDownloadColor,
                        sparkline: appState.networkSnapshot?.history60s.map { Double($0.downloadBytesPerSecond) / 1024 } ?? [],
                        status: .normal,
                        gradientAngle: gradientAngle
                    ) {
                        onNavigate(.network)
                    }

                    MetricSummaryCard(
                        title: "GPU",
                        value: String(format: "%.1f%%", appState.gpu.usagePercent),
                        icon: "bolt.triangle",
                        tint: AppTheme.gpuColor,
                        sparkline: [appState.gpuSnapshot?.gpus.first?.utilizationPercent].compactMap { $0 },
                        status: gpuStatus,
                        gradientAngle: gradientAngle
                    ) {
                        onNavigate(.gpu)
                    }

                    MetricSummaryCard(
                        title: "Thermal",
                        value: appState.thermalSnapshot.map { String(format: "%.0f°C", hottestTemp(in: $0)) } ?? "--",
                        icon: "thermometer.sun.fill",
                        tint: .orange,
                        sparkline: [appState.thermalSnapshot.map { hottestTemp(in: $0) }].compactMap { $0 },
                        status: thermalStatus,
                        gradientAngle: gradientAngle
                    ) {
                        onNavigate(.thermal)
                    }

                    MetricSummaryCard(
                        title: "Battery",
                        value: appState.batterySnapshot.map { String(format: "%.0f%%", $0.chargePercent) } ?? "N/A",
                        icon: "battery.100",
                        tint: AppTheme.batteryColor,
                        sparkline: appState.batterySnapshot?.chargeHistory24h.map(\.chargePercent) ?? [],
                        status: batteryStatus,
                        gradientAngle: gradientAngle
                    ) {
                        onNavigate(.battery)
                    }
                }

                if alertsStore.badgeCountLastHour > 0 {
                    Label("\(alertsStore.badgeCountLastHour) recent alerts", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .padding(16)
        }
        .onAppear {
            systemInfo = .current()
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                gradientAngle = 360
            }
        }
    }

    private var systemBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(systemInfo.computerName)
                    .font(.title2.weight(.semibold))
                Text("\(systemInfo.osVersion) • \(systemInfo.chipName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Uptime: \(formatUptime())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "macbook.and.iphone")
                .font(.largeTitle)
                .foregroundStyle(.tint)
        }
        .padding(14)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var cpuStatus: MetricSummaryCard.Status {
        if appState.cpu.usagePercent >= 90 { return .critical }
        if appState.cpu.usagePercent >= 75 { return .warning }
        return .normal
    }

    private var memoryStatus: MetricSummaryCard.Status {
        if appState.ram.usedPercent >= 90 { return .critical }
        if appState.ram.usedPercent >= 80 { return .warning }
        return .normal
    }

    private var gpuStatus: MetricSummaryCard.Status {
        if appState.gpu.usagePercent >= 95 { return .critical }
        if appState.gpu.usagePercent >= 80 { return .warning }
        return .normal
    }

    private var thermalStatus: MetricSummaryCard.Status {
        guard let thermal = appState.thermalSnapshot else { return .normal }
        let hot = hottestTemp(in: thermal)
        if hot >= 90 { return .critical }
        if hot >= 80 { return .warning }
        return .normal
    }

    private var batteryStatus: MetricSummaryCard.Status {
        guard let battery = appState.batterySnapshot else { return .normal }
        if battery.chargePercent <= 10 { return .critical }
        if battery.chargePercent <= 20 { return .warning }
        return .normal
    }

    private func hottestTemp(in snapshot: ThermalSnapshot) -> Double {
        snapshot.sensors.map(\.celsius).max() ?? 0
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    private func formatUptime() -> String {
        guard let uptime = appState.systemUptime else { return "--" }
        let days = Int(uptime) / 86_400
        let hours = (Int(uptime) % 86_400) / 3_600
        let minutes = (Int(uptime) % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

struct MetricSummaryCard: View {
    enum Status {
        case normal
        case warning
        case critical
    }

    let title: String
    let value: String
    let icon: String
    let tint: Color
    let sparkline: [Double]
    let status: Status
    let gradientAngle: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(tint)

                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                SparklineView(values: sparkline.isEmpty ? [0] : sparkline, color: tint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(borderOverlay)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var borderOverlay: some View {
        let base = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if status == .normal {
            base.stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        } else {
            base
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.orange, .red, .pink, .orange]),
                        center: .center,
                        angle: .degrees(gradientAngle)
                    ),
                    lineWidth: 1.8
                )
        }
    }
}

struct SystemInfo {
    let computerName: String
    let osVersion: String
    let chipName: String

    static let empty = SystemInfo(computerName: "Mac", osVersion: "macOS", chipName: "Apple Silicon")

    static func current() -> SystemInfo {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["hw.model"]

        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chipName = output.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "Apple Silicon"

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        return SystemInfo(
            computerName: Host.current().localizedName ?? "Mac",
            osVersion: osVersion,
            chipName: chipName
        )
    }
}
