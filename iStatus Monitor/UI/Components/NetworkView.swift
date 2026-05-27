import Charts
import SwiftUI

struct NetworkView: View {
    let snapshot: NetworkSnapshot

    private var maxSpeed: UInt64 {
        let maxInterfaceSpeed = snapshot.interfaces
            .flatMap { [$0.downloadBytesPerSecond, $0.uploadBytesPerSecond] }
            .max() ?? 1
        return max(maxInterfaceSpeed, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Network")
                    .font(.headline)
                Spacer()
                Text(snapshot.connectivitySatisfied ? "Connected" : "Offline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.connectivitySatisfied ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Since launch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Text("↓ \(Int(snapshot.totalDownloadSinceLaunch).toMemoryString())")
                    Text("↑ \(Int(snapshot.totalUploadSinceLaunch).toMemoryString())")
                }
                .font(.subheadline.monospacedDigit())
            }

            ForEach(snapshot.interfaces) { iface in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(iface.displayName) (\(iface.name))")
                            .fontWeight(iface.isPrimary ? .bold : .regular)
                        Spacer()
                        Text("↓ \(Int(iface.downloadBytesPerSecond).toNetworkSpeedString())")
                            .font(.caption.monospacedDigit())
                        Text("↑ \(Int(iface.uploadBytesPerSecond).toNetworkSpeedString())")
                            .font(.caption.monospacedDigit())
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.15))

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

                    HStack(spacing: 14) {
                        Text("Total ↓ \(Int(iface.totalBytesReceived).toMemoryString())")
                        Text("Total ↑ \(Int(iface.totalBytesSent).toMemoryString())")
                        if let ipv4 = iface.ipv4Address {
                            Text("IPv4: \(ipv4)")
                        }
                        if let ipv6 = iface.ipv6Address {
                            Text("IPv6: \(ipv6)")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Throughput (60s)")
                    .font(.caption.weight(.semibold))

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
                .frame(height: 72)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: snapshot)
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
