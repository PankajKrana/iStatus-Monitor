import Charts
import SwiftUI

struct MemoryView: View {
    let snapshot: MemorySnapshot

    private var ringData: [(label: String, value: Double, color: Color)] {
        [
            ("Used", Double(snapshot.usedRatio), AppTheme.memoryUsedColor),
            ("Free", Double(max(0, 1 - snapshot.usedRatio)), AppTheme.memoryFreeColor)
        ]
    }

    private var pressureColor: Color {
        switch snapshot.pressure {
        case .normal: AppTheme.memoryPressureNormalColor
        case .warning: AppTheme.memoryPressureWarningColor
        case .critical: AppTheme.memoryPressureCriticalColor
        }
    }

    private var pressureLabel: String {
        switch snapshot.pressure {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Memory Pressure Ring
                GlassCard(material: .thin, padding: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Memory Pressure")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 20) {
                            CircularGauge(
                                value: Double(snapshot.usedRatio) * 100,
                                color: AppTheme.ramColor,
                                icon: "memorychip",
                                title: "Memory Usage",
                                label: snapshot.usedString,
                                strokeWidth: 10
                            )
                            .frame(width: 140, height: 160)

                            VStack(alignment: .leading, spacing: 12) {
                                MetricRowView(
                                    title: "Used",
                                    value: snapshot.usedString,
                                    tint: AppTheme.memoryUsedColor
                                )
                                
                                MetricRowView(
                                    title: "Total",
                                    value: Int(snapshot.totalBytes).toMemoryString(),
                                    tint: AppTheme.memoryUsedColor
                                )
                                
                                HStack {
                                    Text("Status")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    StatusBadge(status: pressureStatus)
                                }
                                
                                MetricRowView(
                                    title: "Swap Used",
                                    value: snapshot.swapUsedString,
                                    tint: AppTheme.memoryUsedColor
                                )
                            }
                            
                            Spacer()
                        }
                    }
                }

                // Memory Categories
                VStack(alignment: .leading, spacing: 10) {
                    Text("Memory Breakdown")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    GlassCard(material: .thin) {
                        VStack(spacing: 12) {
                            GeometryReader { geo in
                                HStack(spacing: 0) {
                                    segment(width: geo.size.width, ratio: ratio(snapshot.appBytes), color: AppTheme.memoryAppColor)
                                    segment(width: geo.size.width, ratio: ratio(snapshot.wiredBytes), color: AppTheme.memoryWiredColor)
                                    segment(width: geo.size.width, ratio: ratio(snapshot.compressedBytes), color: AppTheme.memoryCompressedColor)
                                    segment(width: geo.size.width, ratio: ratio(snapshot.cachedBytes), color: AppTheme.memoryCachedColor)
                                    segment(width: geo.size.width, ratio: ratio(snapshot.freeBytes), color: AppTheme.memoryFreeColor)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .frame(height: 18)

                            HStack(spacing: 10) {
                                legend("App", snapshot.appString, AppTheme.memoryAppColor)
                                legend("Wired", snapshot.wiredString, AppTheme.memoryWiredColor)
                                legend("Compressed", snapshot.compressedString, AppTheme.memoryCompressedColor)
                                legend("Cached", snapshot.cachedString, AppTheme.memoryCachedColor)
                                legend("Free", snapshot.freeString, AppTheme.memoryFreeColor)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .animation(AppTheme.springAnimation, value: snapshot)
    }

    private func ratio(_ value: UInt64) -> CGFloat {
        guard snapshot.totalBytes > 0 else { return 0 }
        return CGFloat(Double(value) / Double(snapshot.totalBytes))
    }

    @ViewBuilder
    private func segment(width: CGFloat, ratio: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, width * ratio))
    }

    private func legend(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title): \(value)")
        }
    }
    
    private var pressureStatus: StatusBadge.Status {
        switch snapshot.pressure {
        case .normal: return .normal
        case .warning: return .warning
        case .critical: return .critical
        }
    }
}

#Preview {
    MemoryView(
        snapshot: MemorySnapshot(
            timestamp: Date(),
            totalBytes: 16_000_000_000,
            usedBytes: 10_400_000_000,
            wiredBytes: 2_800_000_000,
            appBytes: 4_600_000_000,
            compressedBytes: 3_000_000_000,
            cachedBytes: 3_400_000_000,
            freeBytes: 2_200_000_000,
            swapUsedBytes: 1_200_000_000,
            swapTotalBytes: 8_000_000_000,
            pressure: .warning
        )
    )
    .padding()
    .frame(width: 560)
}
