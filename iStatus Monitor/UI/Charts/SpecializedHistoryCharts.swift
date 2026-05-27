import Charts
import SwiftUI

struct CPUCorePoint: TimeSeriesDataPoint, Identifiable, Sendable {
    let timestamp: Date
    let value: Double
    let core: Int

    var id: String { "\(core)-\(timestamp.timeIntervalSince1970)" }
}

struct MemoryHistoryPoint: Identifiable, Sendable {
    let timestamp: Date
    let wired: Double
    let active: Double
    let compressed: Double
    let free: Double

    var id: Date { timestamp }
}

struct NetworkHistoryPoint: Identifiable, Sendable {
    let timestamp: Date
    let upload: Double
    let download: Double

    var id: Date { timestamp }
}

struct TemperatureHistoryPoint: Identifiable, Sendable {
    let timestamp: Date
    let sensor: String
    let celsius: Double

    var id: String { "\(sensor)-\(timestamp.timeIntervalSince1970)" }
}

struct CPUHistoryChart: View {
    let points: [CPUCorePoint]
    let windowSeconds: TimeInterval

    @State private var enabledCores: Set<Int> = []

    private var cores: [Int] { Array(Set(points.map(\.core))).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(cores, id: \.self) { core in
                    Button(enabledCores.contains(core) ? "Core \(core)" : "Core \(core)") {
                        if enabledCores.contains(core) {
                            enabledCores.remove(core)
                        } else {
                            enabledCores.insert(core)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(color(for: core))
                }
            }

            Chart(filteredPoints()) { point in
                LineMark(x: .value("Time", point.timestamp), y: .value("CPU", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color(for: point.core))
            }
            .chartYScale(domain: 0 ... 100)
            .frame(height: 220)
        }
        .onAppear {
            if enabledCores.isEmpty { enabledCores = Set(cores) }
        }
    }

    private func filteredPoints() -> [CPUCorePoint] {
        guard let latest = points.last?.timestamp else { return [] }
        let cutoff = latest.addingTimeInterval(-windowSeconds)
        return points.filter { $0.timestamp >= cutoff && enabledCores.contains($0.core) }
    }

    private func color(for core: Int) -> Color {
        let palette: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .indigo, .purple]
        return palette[core % palette.count]
    }
}

struct MemoryHistoryChart: View {
    let points: [MemoryHistoryPoint]

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Time", point.timestamp), y: .value("Wired", point.wired), stacking: .standard)
                .foregroundStyle(Color.purple.opacity(0.6))
            AreaMark(x: .value("Time", point.timestamp), y: .value("Active", point.active), stacking: .standard)
                .foregroundStyle(Color.blue.opacity(0.6))
            AreaMark(x: .value("Time", point.timestamp), y: .value("Compressed", point.compressed), stacking: .standard)
                .foregroundStyle(Color.orange.opacity(0.6))
            AreaMark(x: .value("Time", point.timestamp), y: .value("Free", point.free), stacking: .standard)
                .foregroundStyle(Color.green.opacity(0.4))
        }
        .frame(height: 220)
    }
}

struct NetworkHistoryChart: View {
    let points: [NetworkHistoryPoint]

    private var maxDownload: Double { max(points.map(\.download).max() ?? 1, 1) }
    private var maxUpload: Double { max(points.map(\.upload).max() ?? 1, 1) }

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Time", point.timestamp), y: .value("Download", point.download))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.green)

            LineMark(x: .value("Time", point.timestamp), y: .value("Upload", point.upload))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.blue)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text(Int(val).toNetworkSpeedString())
                    }
                }
            }
            AxisMarks(position: .trailing, values: .automatic) { value in
                AxisTick()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        let mapped = val * (maxUpload / maxDownload)
                        Text(Int(mapped).toNetworkSpeedString())
                    }
                }
            }
        }
        .frame(height: 220)
    }
}

struct TemperatureHistoryChart: View {
    let points: [TemperatureHistoryPoint]

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Temp", point.celsius),
                series: .value("Sensor", point.sensor)
            )
            .interpolationMethod(.catmullRom)

            RuleMark(y: .value("Warning", 75))
                .lineStyle(.init(lineWidth: 1, dash: [4]))
                .foregroundStyle(.orange.opacity(0.7))
                .annotation(position: .topTrailing) { Text("75°") }

            RuleMark(y: .value("Critical", 90))
                .lineStyle(.init(lineWidth: 1, dash: [4]))
                .foregroundStyle(.red.opacity(0.7))
                .annotation(position: .topTrailing) { Text("90°") }
        }
        .frame(height: 220)
    }
}
