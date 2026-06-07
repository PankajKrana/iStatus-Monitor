import Charts
import SwiftUI

struct DiskView: View {
    let snapshot: DiskSnapshot

    private var primary: DiskVolume? { snapshot.primaryVolume }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroSection
                throughputSection
                volumesSection
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        GlassCard(material: .thin, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Disk Overview")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 20) {
                    CircularGauge(
                        value: primary?.usedPercent ?? 0,
                        color: AppTheme.diskColor,
                        icon: "internaldrive.fill",
                        title: primary?.name ?? "Disk",
                        label: "Used",
                        strokeWidth: 10
                    )
                    .frame(width: 140, height: 160)

                    VStack(alignment: .leading, spacing: 12) {
                        MetricRowView(
                            title: "Read",
                            value: speedString(snapshot.readBytesPerSecond),
                            tint: AppTheme.diskColor
                        )
                        MetricRowView(
                            title: "Write",
                            value: speedString(snapshot.writeBytesPerSecond),
                            tint: AppTheme.diskColor
                        )
                        MetricRowView(
                            title: "Used",
                            value: primary.map { "\($0.usedString) / \($0.totalString)" } ?? "--",
                            tint: AppTheme.diskColor
                        )
                        MetricRowView(
                            title: "Free",
                            value: primary?.freeString ?? "--",
                            tint: AppTheme.diskColor
                        )
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Throughput chart

    @ViewBuilder
    private var throughputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Disk Activity (last 60s)")
                .font(.headline)
                .foregroundStyle(.primary)

            GlassCard(material: .thin, padding: 16) {
                if snapshot.history60s.count < 2 {
                    Text("Collecting data…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    Chart {
                        ForEach(snapshot.history60s) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Read", Double(point.readBytesPerSecond) / 1024),
                                series: .value("Type", "Read")
                            )
                            .foregroundStyle(AppTheme.diskColor)

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Write", Double(point.writeBytesPerSecond) / 1024),
                                series: .value("Type", "Write")
                            )
                            .foregroundStyle(AppTheme.networkUploadColor)
                        }
                    }
                    .chartForegroundStyleScale([
                        "Read": AppTheme.diskColor,
                        "Write": AppTheme.networkUploadColor
                    ])
                    .chartYAxisLabel("KB/s")
                    .frame(height: 160)
                }
            }
        }
    }

    // MARK: - Volumes

    private var volumesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volumes")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(snapshot.volumes) { volume in
                GlassCard(material: .thin, padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(volume.name, systemImage: volume.isRemovable ? "externaldrive.fill" : "internaldrive.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(String(format: "%.0f%%", volume.usedPercent))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(usageColor(volume.usedPercent))
                        }

                        ProgressView(value: volume.usedRatio)
                            .tint(usageColor(volume.usedPercent))

                        HStack {
                            Text("\(volume.usedString) used")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(volume.freeString) free of \(volume.totalString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(volume.mountPoint)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func usageColor(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return AppTheme.diskColor
    }

    private func speedString(_ bytesPerSecond: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }
}
