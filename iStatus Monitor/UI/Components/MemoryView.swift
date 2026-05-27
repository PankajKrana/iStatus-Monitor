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
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory")
                .font(.headline)

            HStack(spacing: 20) {
                Chart(ringData, id: \.label) { item in
                    SectorMark(
                        angle: .value("Share", item.value),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.2
                    )
                    .foregroundStyle(item.color)
                }
                .frame(width: 132, height: 132)
                .chartLegend(.hidden)
                .overlay {
                    VStack(spacing: 4) {
                        Text("Used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(snapshot.usedRatio * 100))%")
                            .font(.title3.weight(.semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(snapshot.usedString) / \(Int(snapshot.totalBytes).toMemoryString())")
                        .font(.subheadline.monospacedDigit())
                    Text("Swap: \(snapshot.swapUsedString) / \(snapshot.swapTotalString)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("Updated \(snapshot.timestamp.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

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

            HStack {
                Text("Memory Pressure")
                    .font(.subheadline)
                Text(pressureLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(pressureColor.opacity(0.16))
                    .foregroundStyle(pressureColor)
                    .clipShape(Capsule())
                Spacer()
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: snapshot)
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
