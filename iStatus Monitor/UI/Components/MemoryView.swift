import Charts
import SwiftUI

struct MemoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshot: MemorySnapshot

    // In-memory trend buffer for the last 5 minutes; local/volatile.
    @State private var trend: [MemorySnapshot] = []

    private static let trendWindow: TimeInterval = 300

    private var pressureColor: Color {
        switch snapshot.pressure {
        case .normal: AppTheme.memoryPressureNormalColor
        case .warning: AppTheme.memoryPressureWarningColor
        case .critical: AppTheme.memoryPressureCriticalColor
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                memoryUsageCard
                memoryPressureSection
                memoryCompositionSection
                memoryTrendSection
                memoryDetailsSection
            }
        }
        .animation(reduceMotion ? .none : AppTheme.springAnimation, value: snapshot)
        .onAppear { appendTrend(snapshot) }
        .onChange(of: snapshot.timestamp) { _, _ in appendTrend(snapshot) }
    }

    private var memoryUsageCard: some View {
        GlassCard(material: .thin, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Memory Usage")

                // Stacks vertically when too narrow to fit side-by-side.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 20) {
                        usageGauge
                        usageMetricsColumn
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 16) {
                        usageGauge
                        usageMetricsColumn
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var usageGauge: some View {
        CircularGauge(
            value: Double(snapshot.usedRatio) * 100,
            color: AppTheme.ramColor,
            icon: "memorychip",
            title: "In Use",
            label: "\(snapshot.usedString) Used",
            strokeWidth: 10
        )
        .frame(width: 140, height: 160)
    }

    private var usageMetricsColumn: some View {
        VStack(spacing: 10) {
            usageMetricRow("Used Memory", snapshot.usedString)
            usageMetricRow("Free Memory", snapshot.freeString)
            usageMetricRow("Total Memory", Int(snapshot.totalBytes).toMemoryString())
            usageMetricRow("Swap Used", snapshot.swapUsedString)
        }
    }

    private func usageMetricRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    // MARK: Memory Pressure + Health

    private var memoryPressureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Memory Pressure")

            GlassCard(material: .thin) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.headline)
                            .foregroundStyle(pressureColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pressureTitle)
                                .font(.body.weight(.medium))
                            Text(pressureDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        StatusBadge(status: pressureStatus)
                    }

                    Divider()

                    HStack(spacing: 10) {
                        Image(systemName: "heart.fill")
                            .font(.headline)
                            .foregroundStyle(health.color)
                        Text("Memory Health")
                            .font(.body)
                        Spacer(minLength: 8)
                        StatusBadge(status: .custom(health.label, health.color))
                    }
                }
            }
        }
    }

    // MARK: Memory Composition

    private var memoryCompositionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Memory Composition")

            GlassCard(material: .thin) {
                VStack(spacing: 14) {
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

                    VStack(spacing: 8) {
                        compositionRow("App Memory", snapshot.appBytes, snapshot.appString, AppTheme.memoryAppColor)
                        compositionRow("Wired Memory", snapshot.wiredBytes, snapshot.wiredString, AppTheme.memoryWiredColor)
                        compositionRow("Compressed Memory", snapshot.compressedBytes, snapshot.compressedString, AppTheme.memoryCompressedColor)
                        compositionRow("Cached Files", snapshot.cachedBytes, snapshot.cachedString, AppTheme.memoryCachedColor)
                        compositionRow("Free Memory", snapshot.freeBytes, snapshot.freeString, AppTheme.memoryFreeColor)
                    }
                }
            }
        }
    }

    // MARK: Memory Trend (last 5 minutes)

    @ViewBuilder
    private var memoryTrendSection: some View {
        if trend.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Memory Trend (Last 5 Minutes)")

                GlassCard(material: .thin) {
                  VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        trendStat("Current", trendStats.current)
                        Divider().frame(height: 24)
                        trendStat("Average", trendStats.average)
                        Divider().frame(height: 24)
                        trendStat("Peak", trendStats.peak)
                        Spacer()
                    }

                    Chart(trend, id: \.timestamp) { point in
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Usage", Double(point.usedRatio) * 100)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.ramColor.opacity(0.35), AppTheme.ramColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Usage", Double(point.usedRatio) * 100)
                        )
                        .foregroundStyle(AppTheme.ramColor)
                        .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 50, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text("\(v)%")
                                }
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 90)
                  }
                }
            }
        }
    }

    // MARK: Memory Details

    private var memoryDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Memory Details")

            GlassCard(material: .thin) {
                VStack(spacing: 12) {
                    detailRow(icon: "memorychip.fill", title: "Total Memory",
                              value: Int(snapshot.totalBytes).toMemoryString(), color: AppTheme.memoryUsedColor)
                    detailRow(icon: "app.connected.to.app.below.fill", title: "App Memory",
                              value: snapshot.appString, bytes: snapshot.appBytes, color: AppTheme.memoryAppColor,
                              help: "App Memory:\nMemory actively used by applications.")
                    detailRow(icon: "lock.fill", title: "Wired Memory",
                              value: snapshot.wiredString, bytes: snapshot.wiredBytes, color: AppTheme.memoryWiredColor,
                              help: "Wired Memory:\nSystem memory that cannot be compressed or swapped.")
                    detailRow(icon: "arrow.down.circle.fill", title: "Compressed Memory",
                              value: snapshot.compressedString, bytes: snapshot.compressedBytes, color: AppTheme.memoryCompressedColor,
                              help: "Compressed Memory:\nMemory compressed by macOS to reduce pressure.")
                    detailRow(icon: "internaldrive.fill", title: "Cached Files",
                              value: snapshot.cachedString, bytes: snapshot.cachedBytes, color: AppTheme.memoryCachedColor,
                              help: "Cached Files:\nRecently used files kept in memory for faster access.")
                    detailRow(icon: "circle.dashed", title: "Free Memory",
                              value: snapshot.freeString, bytes: snapshot.freeBytes, color: AppTheme.memoryFreeColor)
                    detailRow(icon: "arrow.triangle.2.circlepath", title: "Swap Used",
                              value: snapshot.swapUsedString, color: AppTheme.memoryUsedColor)
                }
            }
        }
    }

    // MARK: Helpers

    // Derived from the trend buffer already held by the chart.
    private var trendStats: (current: Int, average: Int, peak: Int) {
        let values = trend.map { Double($0.usedRatio) * 100 }
        guard !values.isEmpty else { return (0, 0, 0) }
        let current = values.last ?? 0
        let average = values.reduce(0, +) / Double(values.count)
        let peak = values.max() ?? 0
        return (Int(current.rounded()), Int(average.rounded()), Int(peak.rounded()))
    }

    private func trendStat(_ label: String, _ percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(percent)%")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private func appendTrend(_ snapshot: MemorySnapshot) {
        if trend.last?.timestamp == snapshot.timestamp { return }
        trend.append(snapshot)
        let cutoff = snapshot.timestamp.addingTimeInterval(-Self.trendWindow)
        trend.removeAll { $0.timestamp < cutoff }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func detailRow(icon: String, title: String, value: String, bytes: UInt64? = nil,
                           color: Color, help: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 22, alignment: .center)
            Text(title)
                .font(.body)
            Spacer(minLength: 8)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            // Reserve percentage column so rows stay aligned.
            Text(bytes.map { "(\(percentString($0)))" } ?? "")
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .modifier(OptionalHelp(text: help))
    }

    private func compositionRow(_ title: String, _ bytes: UInt64, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)
            Text("(\(percentString(bytes)))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func percentString(_ bytes: UInt64) -> String {
        guard snapshot.totalBytes > 0 else { return "0%" }
        let pct = Double(bytes) / Double(snapshot.totalBytes) * 100
        return "\(Int(pct.rounded()))%"
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

    private var pressureStatus: StatusBadge.Status {
        switch snapshot.pressure {
        case .normal: return .normal
        case .warning: return .warning
        case .critical: return .critical
        }
    }

    private var pressureTitle: String {
        switch snapshot.pressure {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    private var pressureDescription: String {
        switch snapshot.pressure {
        case .normal: "Memory resources are available."
        case .warning: "Memory resources are becoming constrained."
        case .critical: "Memory resources are critically low."
        }
    }

    private var health: (label: String, color: Color) {
        let ratio = Double(snapshot.usedRatio)
        switch ratio {
        case ..<0.60: return ("Excellent", AppTheme.memoryPressureNormalColor)
        case ..<0.75: return ("Good", AppTheme.memoryPressureNormalColor)
        case ..<0.90: return ("High Usage", AppTheme.memoryPressureWarningColor)
        default: return ("Critical", AppTheme.memoryPressureCriticalColor)
        }
    }
}

private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
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
