import Charts
import SwiftUI

struct CPUView: View {
    let snapshot: CPUSnapshot
    let searchText: String

    init(snapshot: CPUSnapshot, searchText: String = "") {
        self.snapshot = snapshot
        self.searchText = searchText
    }

    private var filteredCores: [CoreUsage] {
        guard !searchText.isEmpty else { return snapshot.perCoreUsage }
        return snapshot.perCoreUsage.filter { "core \($0.coreIndex)".localizedCaseInsensitiveContains(searchText) }
    }

    private var ringData: [(label: String, value: Double, color: Color)] {
        [
            ("Active", Double(snapshot.overallLoad), AppTheme.cpuColor),
            ("Idle", Double(max(0, 1 - snapshot.overallLoad)), .gray.opacity(0.25))
        ]
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 64), spacing: 10)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero Section
                GlassCard(material: .thin, padding: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CPU Overview")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 20) {
                            // Circular gauge
                            CircularGauge(
                                value: Double(snapshot.overallLoad) * 100,
                                color: AppTheme.cpuColor,
                                icon: "cpu",
                                title: "Total Usage",
                                label: "Active",
                                strokeWidth: 10
                            )
                            .frame(width: 140, height: 160)

                            VStack(alignment: .leading, spacing: 12) {
                                MetricRowView(
                                    title: "Load Average",
                                    value: String(format: "%.2f, %.2f, %.2f", snapshot.loadAverage.one, snapshot.loadAverage.five, snapshot.loadAverage.fifteen),
                                    tint: AppTheme.cpuColor
                                )
                                
                                MetricRowView(
                                    title: "Frequency",
                                    value: "3.2 GHz",
                                    tint: AppTheme.cpuColor
                                )
                                
                                MetricRowView(
                                    title: "Temperature",
                                    value: "72°C",
                                    tint: AppTheme.cpuColor
                                )
                                
                                MetricRowView(
                                    title: "Power",
                                    value: "45W",
                                    tint: AppTheme.cpuColor
                                )
                            }
                            
                            Spacer()
                        }
                    }
                }

                // Per-Core Heatmap Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Per-Core Usage")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if filteredCores.isEmpty {
                        ContentUnavailableView("No Matching Processes", systemImage: "magnifyingglass", description: Text("Try a different filter term."))
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(filteredCores, id: \.coreIndex) { core in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("C\(core.coreIndex)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    GeometryReader { geo in
                                        ZStack(alignment: .bottom) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.gray.opacity(0.18))

                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(AppTheme.cpuColor)
                                                .frame(height: geo.size.height * CGFloat(core.active))
                                        }
                                    }
                                    .frame(height: 52)

                                    Text("\(Int(core.active * 100))%")
                                        .font(.caption2.monospacedDigit())
                                        .contentTransition(.numericText())
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(AppTheme.springAnimation, value: snapshot)
    }
}
