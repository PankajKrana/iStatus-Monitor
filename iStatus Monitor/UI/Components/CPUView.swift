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
        VStack(alignment: .leading, spacing: 12) {
            Text("CPU")
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
                        Text("Overall")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(snapshot.overallLoad * 100))%")
                            .font(.title3.weight(.semibold))
                            .contentTransition(.numericText())
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "Load Avg: %.2f  %.2f  %.2f", snapshot.loadAverage.one, snapshot.loadAverage.five, snapshot.loadAverage.fifteen))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text("Updated \(snapshot.timestamp.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

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
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: snapshot)
    }
}
