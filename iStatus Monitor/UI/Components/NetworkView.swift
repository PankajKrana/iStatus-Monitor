import Charts
import SwiftUI

struct NetworkView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showInactive = false

    let snapshot: NetworkSnapshot

    private var maxSpeed: UInt64 {
        let maxInterfaceSpeed = snapshot.interfaces
            .flatMap { [$0.downloadBytesPerSecond, $0.uploadBytesPerSecond] }
            .max() ?? 1
        return max(maxInterfaceSpeed, 1)
    }

    // Considered active if it has an address, is default route, or is moving bytes.
    private var activeInterfaces: [InterfaceStats] {
        snapshot.interfaces.filter(\.isActiveConnection)
    }

    private var inactiveInterfaces: [InterfaceStats] {
        snapshot.interfaces.filter { !$0.isActiveConnection }
    }

    /// Primary connection (default route or first active).
    private var primary: InterfaceStats? { activeInterfaces.first }

    private var activeVPN: InterfaceStats? {
        activeInterfaces.first { $0.type == .vpn }
    }

    /// Physical link a VPN rides on.
    private var vpnUnderlying: InterfaceStats? {
        activeInterfaces.first { $0.type == .wifi || $0.type == .ethernet }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                activeConnectionCard
                interfacesSection
                throughputChart
            }
        }
        .animation(reduceMotion ? .none : AppTheme.springAnimation, value: snapshot)
    }

    private var activeConnectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Connection")
                .font(.headline)
                .foregroundStyle(.primary)

            GlassCard(material: .thin, padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    if let primary {
                        interfaceHeader(primary, showVPNBadge: activeVPN != nil)
                        speedRow(download: primary.downloadBytesPerSecond,
                                 upload: primary.uploadBytesPerSecond)
                        connectionDetails(primary)

                        if let vpnUnderlying, vpnUnderlying.id != primary.id, activeVPN != nil {
                            Divider()
                            underlyingRow(vpnUnderlying)
                        }
                    } else {
                        Label("No active connection", systemImage: "wifi.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                    launchTotals
                }
            }
        }
    }

    private func interfaceHeader(_ iface: InterfaceStats, showVPNBadge: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iface.sfSymbol)
                .font(.title2)
                .foregroundStyle(AppTheme.networkColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(iface.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(iface.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if showVPNBadge {
                Label("VPN", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityLabel("VPN active")
            }
            StatusBadge(status: snapshot.connectivitySatisfied ? .normal : .critical)
        }
    }

    private func speedRow(download: UInt64, upload: UInt64) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Download")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Int(download).toNetworkSpeedString())
                    .font(.title2.monospacedDigit().weight(.light))
                    .foregroundStyle(AppTheme.networkDownloadColor)
            }

            Divider().frame(height: 50)

            VStack(alignment: .leading, spacing: 8) {
                Text("Upload")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Int(upload).toNetworkSpeedString())
                    .font(.title2.monospacedDigit().weight(.light))
                    .foregroundStyle(AppTheme.networkUploadColor)
            }

            Spacer()
        }
    }

    private func connectionDetails(_ iface: InterfaceStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ipv4 = iface.ipv4Address {
                DetailRow(label: "IPv4", value: ipv4)
            }
            if let ipv6 = iface.ipv6Address {
                DetailRow(label: "IPv6", value: ipv6, truncate: true)
            }
            DetailRow(label: "Total Received", value: Int(iface.totalBytesReceived).toMemoryString())
            DetailRow(label: "Total Sent", value: Int(iface.totalBytesSent).toMemoryString())
        }
    }

    private func underlyingRow(_ iface: InterfaceStats) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iface.sfSymbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("via \(iface.displayName)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if let ipv4 = iface.ipv4Address {
                Text(ipv4)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var launchTotals: some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailRow(label: "Total Download (Launch)",
                      value: Int(snapshot.totalDownloadSinceLaunch).toMemoryString())
            DetailRow(label: "Total Upload (Launch)",
                      value: Int(snapshot.totalUploadSinceLaunch).toMemoryString())
        }
    }

    // MARK: Interfaces

    private var interfacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Network Interfaces")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(activeInterfaces) { interfaceCard($0) }

            if !inactiveInterfaces.isEmpty {
                DisclosureGroup(isExpanded: $showInactive) {
                    VStack(spacing: 10) {
                        ForEach(inactiveInterfaces) { interfaceCard($0) }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Show inactive interfaces (\(inactiveInterfaces.count))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func interfaceCard(_ iface: InterfaceStats) -> some View {
        GlassCard(material: .thin) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: iface.sfSymbol)
                            .foregroundStyle(AppTheme.networkColor)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(iface.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(iface.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Label(Int(iface.downloadBytesPerSecond).toNetworkSpeedString(), systemImage: "arrow.down")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.networkDownloadColor)
                        Label(Int(iface.uploadBytesPerSecond).toNetworkSpeedString(), systemImage: "arrow.up")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.networkUploadColor)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)

                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.networkDownloadColor)
                                .frame(width: geo.size.width * CGFloat(Double(iface.downloadBytesPerSecond) / Double(maxSpeed)))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.networkUploadColor)
                                .frame(width: geo.size.width * CGFloat(Double(iface.uploadBytesPerSecond) / Double(maxSpeed)))
                        }
                    }
                }
                .frame(height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    if let ipv4 = iface.ipv4Address {
                        DetailRow(label: "IPv4", value: ipv4)
                    }
                    if let ipv6 = iface.ipv6Address {
                        DetailRow(label: "IPv6", value: ipv6, truncate: true)
                    }
                    DetailRow(label: "Total Received", value: Int(iface.totalBytesReceived).toMemoryString())
                    DetailRow(label: "Total Sent", value: Int(iface.totalBytesSent).toMemoryString())
                }
            }
        }
    }

    // MARK: Chart

    private var throughputChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bandwidth (60s)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                legendItem(color: AppTheme.networkDownloadColor, label: "Download",
                           value: snapshot.history60s.last?.downloadBytesPerSecond ?? 0)
                legendItem(color: AppTheme.networkUploadColor, label: "Upload",
                           value: snapshot.history60s.last?.uploadBytesPerSecond ?? 0)
            }

            GlassCard(material: .thin) {
                // Binds to the monitor's rolling buffer; fresh snapshots animate via `.animation(value:)`.
                Chart(snapshot.history60s) { point in
                    areaMark(x: point.timestamp, y: point.downloadBytesPerSecond, color: AppTheme.networkDownloadColor)
                    areaMark(x: point.timestamp, y: point.uploadBytesPerSecond, color: AppTheme.networkUploadColor)

                    lineMark(series: "Download", x: point.timestamp, y: point.downloadBytesPerSecond, color: AppTheme.networkDownloadColor)
                    lineMark(series: "Upload", x: point.timestamp, y: point.uploadBytesPerSecond, color: AppTheme.networkUploadColor)
                }
                .frame(height: 140)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let bytes = value.as(Int.self) {
                                Text(bytes.toNetworkSpeedString())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func areaMark(x: Date, y: UInt64, color: Color) -> some ChartContent {
        AreaMark(x: .value("Time", x), y: .value("Rate", y))
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            )
    }

    private func lineMark(series: String, x: Date, y: UInt64, color: Color) -> some ChartContent {
        LineMark(x: .value("Time", x), y: .value("Rate", y), series: .value("Series", series))
            .interpolationMethod(.catmullRom)
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 2))
    }

    private func legendItem(color: Color, label: String, value: UInt64) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Int(value).toNetworkSpeedString())
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

/// One `label ────── value` line, reused by the hero card and interface cards.
private struct DetailRow: View {
    let label: String
    let value: String
    var truncate: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .truncationMode(truncate ? .middle : .tail)
        }
    }
}

private extension InterfaceStats {
    /// Carries a real connection (default route, has an address, or moving bytes).
    var isActiveConnection: Bool {
        isConnected && (isPrimary
            || ipv4Address != nil
            || downloadBytesPerSecond > 0
            || uploadBytesPerSecond > 0)
    }

    /// SF Symbol per interface kind.
    var sfSymbol: String {
        if name.hasPrefix("bridge") { return "point.3.connected.trianglepath.dotted" }
        if name.hasPrefix("awdl") || name.hasPrefix("llw") { return "dot.radiowaves.left.and.right" }
        switch type {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .vpn: return "lock.shield.fill"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        }
    }
}

#Preview {
    NetworkView(
        snapshot: NetworkSnapshot(
            timestamp: Date(),
            interfaces: [
                InterfaceStats(name: "en0", displayName: "Wi-Fi", type: .wifi,
                               downloadBytesPerSecond: 1_200_000, uploadBytesPerSecond: 240_000,
                               totalBytesReceived: 8_000_000_000, totalBytesSent: 1_200_000_000,
                               ipv4Address: "192.168.1.42", ipv6Address: "fe80::1c2d:3e4f:5a6b:7c8d",
                               isConnected: true, isPrimary: true),
                InterfaceStats(name: "utun3", displayName: "VPN", type: .vpn,
                               downloadBytesPerSecond: 900_000, uploadBytesPerSecond: 120_000,
                               totalBytesReceived: 3_000_000_000, totalBytesSent: 400_000_000,
                               ipv4Address: "10.8.0.2", ipv6Address: nil,
                               isConnected: true, isPrimary: false),
                InterfaceStats(name: "awdl0", displayName: "AWDL", type: .other,
                               downloadBytesPerSecond: 0, uploadBytesPerSecond: 0,
                               totalBytesReceived: 0, totalBytesSent: 0,
                               ipv4Address: nil, ipv6Address: nil,
                               isConnected: true, isPrimary: false)
            ],
            connectivitySatisfied: true,
            totalDownloadSinceLaunch: 5_000_000_000,
            totalUploadSinceLaunch: 800_000_000,
            history60s: []
        )
    )
    .frame(width: 420, height: 700)
    .padding()
}
