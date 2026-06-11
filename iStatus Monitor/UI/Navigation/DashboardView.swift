import Foundation
import SwiftUI
import Combine

struct DashboardView: View {
    @Bindable var appState: AppState
    @Bindable var alertsStore: AlertsStore
    let onNavigate: (NavigationTab) -> Void

    @State private var systemInfo: SystemInfo = .empty
    @State private var thermalFallbackHistory: [Double] = []
    private let thermalTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

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
                            ("Cores", String(appState.cpu.coreCount) + " cores"),
                            ("Temp", appState.cpu.temperatureCelsius.map { String(format: "%.0f°C", $0) } ?? "--")
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
                            ("Device", gpuDeviceLabel),
                            ("VRAM", gpuMemoryLabel)
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
                        metric: appState.diskSnapshot?.primaryVolume.map { String(format: "%.0f%%", $0.usedPercent) } ?? "--%",
                        icon: "internaldrive.fill",
                        tint: AppTheme.diskColor,
                        sparkline: appState.diskSnapshot?.history60s.map {
                            Double($0.readBytesPerSecond + $0.writeBytesPerSecond) / 1024
                        } ?? [],
                        status: diskStatus,
                        miniStats: [
                            ("I/O", "↓\(formatBytes(appState.disk.readBytesPerSecond)) ↑\(formatBytes(appState.disk.writeBytesPerSecond))"),
                            ("Used", appState.diskSnapshot?.primaryVolume.map { "\($0.usedString) / \($0.totalString)" } ?? "--")
                        ]
                    ) {
                        onNavigate(.disk)
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
                            ("Time", batteryTimeLabel)
                        ]
                    ) {
                        onNavigate(.battery)
                    }

                    // Temperature Card
                    dashboardCard(
                        title: "Thermal",
                        metric: appState.thermalSnapshot.map {
                            "\(hottestTemp(in: $0).formatted(.number.precision(.fractionLength(0))))°C"
                        } ?? thermalStateText,
                        icon: "thermometer.sun.fill",
                        tint: AppTheme.temperatureColor,
                        sparkline: appState.thermalSnapshot.map { $0.sensors.map(\.celsius) } ?? thermalFallbackHistory,
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

                    // System Health Card — composite of the real per-metric
                    // statuses (no fabricated values), tapping opens Alerts.
                    dashboardCard(
                        title: "Health",
                        metric: overallHealthLabel,
                        icon: "heart.fill",
                        tint: overallHealthTint,
                        sparkline: [],
                        status: overallHealthStatus,
                        miniStats: [
                            ("Uptime", formatUptime()),
                            ("Alerts", "\(alertsStore.badgeCountLastHour) recent")
                        ]
                    ) {
                        onNavigate(.alerts)
                    }
                }

                if alertsStore.badgeCountLastHour > 0 {
                    Label("\(alertsStore.badgeCountLastHour) recent alerts", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .padding(16)
        }
        .onReceive(thermalTimer) { _ in
            // Only maintain fallback history if no numeric snapshot is available
            guard appState.thermalSnapshot == nil else { return }
            let value: Double
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: value = 0
            case .fair:    value = 1
            case .serious: value = 2
            case .critical:value = 3
            @unknown default: value = 0
            }
            thermalFallbackHistory.append(value)
            if thermalFallbackHistory.count > 60 { thermalFallbackHistory.removeFirst(thermalFallbackHistory.count - 60) }
        }
        .onAppear {
            systemInfo = .current()
        }
    }

    // Composite system health derived from the real per-metric statuses — worst
    // severity wins. Replaces the previous hardcoded "Good" / fake sparkline.
    private var overallHealthStatus: StatusBadge.Status {
        let worst = [cpuStatus, gpuStatus, memoryStatus, diskStatus, batteryStatus, thermalStatus]
            .map(severityRank(of:))
            .max() ?? 0
        switch worst {
        case 2: return .critical
        case 1: return .warning
        default: return .normal
        }
    }

    private var overallHealthLabel: String {
        switch severityRank(of: overallHealthStatus) {
        case 2: return "Needs Attention"
        case 1: return "Fair"
        default: return "Good"
        }
    }

    private var overallHealthTint: Color {
        switch severityRank(of: overallHealthStatus) {
        case 2: return .red
        case 1: return .orange
        default: return .green
        }
    }

    private func severityRank(of status: StatusBadge.Status) -> Int {
        switch status {
        case .critical: return 2
        case .warning: return 1
        default: return 0
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

    private var gpuDeviceLabel: String {
        guard let gpu = appState.gpuSnapshot?.gpus.first else { return "--" }
        return gpu.isIntegrated ? "Integrated" : "Discrete"
    }

    private var gpuMemoryLabel: String {
        guard let gpu = appState.gpuSnapshot?.gpus.first, let total = gpu.vramTotalMB else { return "--" }
        if let used = gpu.vramUsedMB {
            return "\(formatMB(used)) / \(formatMB(total))"
        }
        return formatMB(total)
    }

    private var diskStatus: StatusBadge.Status {
        guard let used = appState.diskSnapshot?.primaryVolume?.usedPercent else { return .normal }
        if used >= 90 { return .critical }
        if used >= 75 { return .warning }
        return .normal
    }

    private var batteryTimeLabel: String {
        guard let snapshot = appState.batterySnapshot else { return "--" }
        switch snapshot.chargeState {
        case .charging:
            return snapshot.timeToFullMinutes.map { formatMinutes($0) + " to full" } ?? "Charging"
        case .discharging:
            return snapshot.timeToEmptyMinutes.map { formatMinutes($0) + " left" } ?? "On battery"
        case .full, .ac:
            return "On AC"
        case .unknown:
            return "--"
        }
    }


    private var batteryStatus: StatusBadge.Status {
        guard let snapshot = appState.batterySnapshot else {
            // If we can't read the battery, assume normal to avoid noisy warnings on desktops
            return .normal
        }
        // Prioritize critical states: very low charge or very poor health
        if snapshot.chargePercent <= 10 || snapshot.healthPercent <= 60 { return .critical }
        // Warning for low charge or degraded health
        if snapshot.chargePercent <= 20 || snapshot.healthPercent <= 80 { return .warning }
        return .normal
    }


    private var thermalStatus: StatusBadge.Status {
        if let thermal = appState.thermalSnapshot {
            let hot = hottestTemp(in: thermal)
            if hot >= 90 { return .critical }
            if hot >= 80 { return .warning }
            return .normal
        } else {
            switch ProcessInfo.processInfo.thermalState {
            case .critical: return .critical
            case .serious:  return .warning
            case .fair:     return .warning
            case .nominal:  return .normal
            @unknown default: return .normal
            }
        }
    }

    // MARK: - Helpers

    private var thermalStateText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair:    return "Fair"
        case .serious: return "Serious"
        case .critical:return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private func hottestTemp(in snapshot: ThermalSnapshot) -> Double {
        snapshot.sensors.map(\.celsius).max() ?? 0
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    private func formatMB(_ megabytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(megabytes) * 1_048_576, countStyle: .file)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "--" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
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

