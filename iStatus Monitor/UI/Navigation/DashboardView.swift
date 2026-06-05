import Foundation
import SwiftUI

struct DashboardView: View {
    @Bindable var appState: AppState
    @Bindable var alertsStore: AlertsStore
    let onNavigate: (NavigationTab) -> Void

    @State private var systemInfo: SystemInfo = .empty

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                systemBanner

                LazyVGrid(columns: columns, spacing: 16) {
                    // CPU Card
                    dashboardCard(
                        title: "CPU",
                        metric: String(format: "%.1f%%", appState.cpu.usagePercent),
                        icon: "cpu",
                        tint: AppTheme.cpuColor,
                        sparkline: appState.cpuHistory.map { Double($0.overallLoad) * 100 },
                        status: cpuStatus,
                        miniStats: [
                            ("Threads", String(appState.cpu.coreCount) + " cores"),
                            ("Freq", "3.2 GHz")
                        ]
                    ) {
                        onNavigate(.cpu)
                    }

                    // GPU Card
                    dashboardCard(
                        title: "GPU",
                        metric: String(format: "%.1f%%", appState.gpu.usagePercent),
                        icon: "display",
                        tint: AppTheme.gpuColor,
                        sparkline: [appState.gpuSnapshot?.gpus.first?.utilizationPercent].compactMap { $0 },
                        status: gpuStatus,
                        miniStats: [
                            ("Device", "Integrated"),
                            ("Mem", "1.2 GB / 4.0 GB")
                        ]
                    ) {
                        onNavigate(.gpu)
                    }

                    // Memory Card
                    dashboardCard(
                        title: "Memory",
                        metric: String(format: "%.1f%%", appState.ram.usedPercent),
                        icon: "memorychip",
                        tint: AppTheme.memoryUsedColor,
                        sparkline: [appState.memorySnapshot?.usedRatio].compactMap { $0 }.map { Double($0) * 100 },
                        status: memoryStatus,
                        miniStats: [
                            ("Used", appState.memorySnapshot?.usedString ?? "--"),
                            ("Total", Int(appState.memorySnapshot?.totalBytes ?? 0).toMemoryString())
                        ]
                    ) {
                        onNavigate(.memory)
                    }

                    // Disk Card
                    dashboardCard(
                        title: "Disk",
                        metric: "-- %",
                        icon: "internaldrive.fill",
                        tint: AppTheme.diskColor,
                        sparkline: [50, 45, 48, 52, 50],
                        status: .normal,
                        miniStats: [
                            ("Speed", "-- MB/s"),
                            ("Used", "-- GB / -- GB")
                        ]
                    ) {
                        // Placeholder for disk navigation
                    }

                    // Network Card
                    dashboardCard(
                        title: "Network",
                        metric: "↓ \(formatBytes(appState.network.bytesInPerSecond))/s",
                        icon: "network",
                        tint: AppTheme.networkDownloadColor,
                        sparkline: appState.networkSnapshot?.history60s.map {
                            Double($0.downloadBytesPerSecond) / 1024
                        } ?? [],
                        status: .normal,
                        miniStats: [
                            ("Upload", "↑ \(formatBytes(appState.network.bytesOutPerSecond))/s"),
                            ("IP",
                             appState.networkSnapshot?
                                .interfaces
                                .first(where: { $0.isPrimary })?
                                .ipv4Address ?? "--")
                        ]
                    ) {
                        onNavigate(.network)
                    }
                    
                    // Battery Card
                    dashboardCard(
                        title: "Battery",
                        metric: appState.batterySnapshot.map { String(format: "%.0f%%", $0.chargePercent) } ?? "N/A",
                        icon: "battery.100",
                        tint: AppTheme.batteryColor,
                        sparkline: appState.batterySnapshot?.chargeHistory24h.map(\.chargePercent) ?? [],
                        status: batteryStatus,
                        miniStats: [
                            ("Health", appState.batterySnapshot.map { String(format: "%.0f%%", $0.healthPercent) } ?? "--"),
                            ("Time", "-- h remaining")
                        ]
                    ) {
                        onNavigate(.battery)
                    }

                    // Temperature Card
                    dashboardCard(
                        title: "Thermal",
                        metric: appState.thermalSnapshot.map { String(format: "%.0f°C", hottestTemp(in: $0)) } ?? "--",
                        icon: "thermometer.sun.fill",
                        tint: AppTheme.temperatureColor,
                        sparkline: appState.thermalSnapshot.map { $0.sensors.map(\.celsius) } ?? [],
                        status: thermalStatus,
                        miniStats: [
                            (
                                "Fan",
                                appState.thermalSnapshot?
                                    .fans
                                    .first
                                    .map { String(format: "%.0f RPM", $0.rpm) } ?? "--"
                            ),
                            (
                                "Status",
                                appState.thermalSnapshot?.thermalState == .critical
                                    ? "Critical"
                                    : appState.thermalSnapshot?.thermalState == .serious
                                        ? "Serious"
                                        : "Normal"
                            )
                        ]                    ) {
                        onNavigate(.thermal)
                    }

                    // System Health Card
                    dashboardCard(
                        title: "Health",
                        metric: "Good",
                        icon: "heart.fill",
                        tint: .green,
                        sparkline: [100, 98, 99, 97, 100],
                        status: .normal,
                        miniStats: [
                            ("Uptime", formatUptime()),
                            ("Alerts", "\(alertsStore.badgeCountLastHour) recent")
                        ]
                    ) {
                        // Placeholder for system health navigation
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
        }
    }

    @ViewBuilder
    private func dashboardCard(
        title: String,
        metric: String,
        icon: String,
        tint: Color,
        sparkline: [Double],
        status: StatusBadge.Status,
        miniStats: [(String, String)],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GlassCard(material: .thin, cornerRadius: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(title, systemImage: icon)
                            .font(.headline)
                            .foregroundStyle(tint)
                        Spacer()
                        let dotStatus: StatusDot.Status = {
                            switch status {
                            case .normal: return .good
                            case .warning: return .warning
                            case .critical: return .critical
                            @unknown default:
                                    return .warning
                            }
                        }()
                        StatusDot(status: dotStatus)
                    }

                    Text(metric)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    if !sparkline.isEmpty {
                        SparklineView(values: sparkline, color: tint)
                            .frame(height: 32)
                    }

                    VStack(spacing: 6) {
                        ForEach(miniStats, id: \.0) { label, value in
                            HStack {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(value)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    private var systemBanner: some View {
        GlassCard(material: .regular, cornerRadius: 12) {
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
        }
    }

    private var cpuStatus: StatusBadge.Status {
        if appState.cpu.usagePercent >= 90 { return .critical }
        if appState.cpu.usagePercent >= 75 { return .warning }
        return .normal
    }

    private var memoryStatus: StatusBadge.Status {
        if appState.ram.usedPercent >= 90 { return .critical }
        if appState.ram.usedPercent >= 80 { return .warning }
        return .normal
    }

    private var gpuStatus: StatusBadge.Status {
        if appState.gpu.usagePercent >= 95 { return .critical }
        if appState.gpu.usagePercent >= 80 { return .warning }
        return .normal
    }

    private var thermalStatus: StatusBadge.Status {
        guard let thermal = appState.thermalSnapshot else { return .normal }
        let hot = hottestTemp(in: thermal)
        if hot >= 90 { return .critical }
        if hot >= 80 { return .warning }
        return .normal
    }

    private var batteryStatus: StatusBadge.Status {
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

