import Charts
import SwiftUI

struct NetworkView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshot: NetworkSnapshot

    private var maxSpeed: UInt64 {
        let maxInterfaceSpeed = snapshot.interfaces
            .flatMap { [$0.downloadBytesPerSecond, $0.uploadBytesPerSecond] }
            .max() ?? 1
        return max(maxInterfaceSpeed, 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Network Status Hero
                GlassCard(material: .thin, padding: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Network Status")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            StatusBadge(status: snapshot.connectivitySatisfied ? .normal : .critical)
                        }

                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Download")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(Int(snapshot.interfaces.first?.downloadBytesPerSecond ?? 0).toNetworkSpeedString())
                                    .font(.title2.monospacedDigit().weight(.light))
                                    .foregroundStyle(AppTheme.networkDownloadColor)
                            }
                            
                            Divider()
                                .frame(height: 50)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Upload")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(Int(snapshot.interfaces.first?.uploadBytesPerSecond ?? 0).toNetworkSpeedString())
                                    .font(.title2.monospacedDigit().weight(.light))
                                    .foregroundStyle(AppTheme.networkUploadColor)
                            }
                            
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Total Download (Launch)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Int(snapshot.totalDownloadSinceLaunch).toMemoryString())
                                    .font(.caption.monospacedDigit())
                            }
                            HStack {
                                Text("Total Upload (Launch)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Int(snapshot.totalUploadSinceLaunch).toMemoryString())
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                }

                // Network Interfaces
                VStack(alignment: .leading, spacing: 10) {
                    Text("Network Interfaces")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    ForEach(snapshot.interfaces) { iface in
                        GlassCard(material: .thin) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(iface.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(iface.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Label(Int(iface.downloadBytesPerSecond).toNetworkSpeedString(), systemImage: "arrow.down")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(AppTheme.networkDownloadColor)
                                            Label(Int(iface.uploadBytesPerSecond).toNetworkSpeedString(), systemImage: "arrow.up")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(AppTheme.networkUploadColor)
                                        }
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
                                        HStack {
                                            Text("IPv4")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(ipv4)
                                                .font(.caption.monospacedDigit())
                                        }
                                    }
                                    if let ipv6 = iface.ipv6Address {
                                        HStack {
                                            Text("IPv6")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(ipv6)
                                                .font(.caption.monospacedDigit())
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    HStack {
                                        Text("Total Received")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(Int(iface.totalBytesReceived).toMemoryString())
                                            .font(.caption.monospacedDigit())
                                    }
                                    HStack {
                                        Text("Total Sent")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(Int(iface.totalBytesSent).toMemoryString())
                                            .font(.caption.monospacedDigit())
                                    }
                                }
                            }
                        }
                    }
                }

                // Throughput Chart
                VStack(alignment: .leading, spacing: 10) {
                    Text("Throughput (60s)")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    GlassCard(material: .thin) {
                        Chart(snapshot.history60s) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Download", point.downloadBytesPerSecond)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(AppTheme.networkDownloadColor)

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Upload", point.uploadBytesPerSecond)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(AppTheme.networkUploadColor)
                        }
                        .frame(height: 120)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                    }
                }
            }
        }
        .animation(reduceMotion ? .none : AppTheme.springAnimation, value: snapshot)
    }
}

#Preview {
    NetworkView(
        snapshot: NetworkSnapshot(
            timestamp: Date(),
            interfaces: [],
            connectivitySatisfied: true,
            totalDownloadSinceLaunch: 0,
            totalUploadSinceLaunch: 0,
            history60s: []
        )
    )
    .padding()
}
