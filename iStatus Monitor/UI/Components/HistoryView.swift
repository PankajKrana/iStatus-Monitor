import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class HistoryViewModel {
    enum RangePreset: String, CaseIterable, Identifiable {
        case today
        case last24h
        case sevenDays
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .last24h: "24h"
            case .sevenDays: "7 days"
            case .custom: "Custom"
            }
        }
    }

    enum ExportFormat: String {
        case csv
        case json
    }

    private let historyStore: HistoryStore

    var metric: MetricType = .cpu
    var preset: RangePreset = .last24h
    var customStart: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    var customEnd: Date = Date()

    var records: [MetricSample] = []
    var stats: (min: Double, max: Double, avg: Double, p95: Double) = (0, 0, 0, 0)

    var showRawRecords = false
    var isExporting = false
    var exportProgress: Double = 0

    init(historyStore: HistoryStore) {
        self.historyStore = historyStore
    }

    func reload() {
        Task {
            let interval = resolvedInterval()
            let history = await historyStore.history(for: metric, in: interval)
            let peaks = await historyStore.peakValues(for: metric, in: interval)

            records = history
            let p95 = percentile(values: history.map(\.value), percentile: 0.95)
            stats = (peaks.min, peaks.max, peaks.avg, p95)
        }
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json]
        panel.nameFieldStringValue = "metrics-\(metric.rawValue)"
        panel.canCreateDirectories = true
        panel.title = "Export History"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let format: ExportFormat = (url.pathExtension.lowercased() == "json") ? .json : .csv

        isExporting = true
        exportProgress = 0

        Task {
            let interval = resolvedInterval()
            let data = await historyStore.exportRecords(for: metric, in: interval)

            switch format {
            case .csv:
                let content = makeCSV(records: data)
                try? content.write(to: url, atomically: true, encoding: .utf8)
            case .json:
                let payload = data.map {
                    ExportRow(timestamp: $0.timestamp, metric: $0.metricType, value: $0.value)
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let out = try? encoder.encode(payload)
                if let out { try? out.write(to: url) }
            }

            exportProgress = 1
            isExporting = false
        }
    }

    private func resolvedInterval() -> DateInterval {
        let now = Date()
        switch preset {
        case .today:
            let start = Calendar.current.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .last24h:
            let start = now.addingTimeInterval(-24 * 3600)
            return DateInterval(start: start, end: now)
        case .sevenDays:
            let start = now.addingTimeInterval(-7 * 24 * 3600)
            return DateInterval(start: start, end: now)
        case .custom:
            return DateInterval(start: min(customStart, customEnd), end: max(customStart, customEnd))
        }
    }

    private func percentile(values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int(Double(sorted.count - 1) * percentile)
        return sorted[max(0, min(rank, sorted.count - 1))]
    }

    private func makeCSV(records: [MetricSample]) -> String {
        var lines = ["timestamp,metric,value"]
        let formatter = ISO8601DateFormatter()

        let total = max(records.count, 1)
        for (idx, row) in records.enumerated() {
            let timestamp = formatter.string(from: row.timestamp)
            lines.append("\(timestamp),\(row.metricType),\(row.value)")
            exportProgress = Double(idx + 1) / Double(total)
        }

        return lines.joined(separator: "\n")
    }

    private struct ExportRow: Codable {
        let timestamp: Date
        let metric: String
        let value: Double
    }
}

struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Metric", selection: $viewModel.metric) {
                    ForEach(MetricType.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button("Export…") {
                    viewModel.export()
                }
            }

            Picker("Range", selection: $viewModel.preset) {
                ForEach(HistoryViewModel.RangePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.preset == .custom {
                HStack {
                    DatePicker("Start", selection: $viewModel.customStart)
                    DatePicker("End", selection: $viewModel.customEnd)
                }
            }

            Chart(viewModel.records, id: \.timestamp) { record in
                LineMark(x: .value("Time", record.timestamp), y: .value("Value", record.value))
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("Time", record.timestamp), y: .value("Value", record.value))
                    .foregroundStyle(.blue.opacity(0.18))
            }
            .frame(height: 260)

            HStack(spacing: 16) {
                Text(String(format: "Min %.2f", viewModel.stats.min))
                Text(String(format: "Max %.2f", viewModel.stats.max))
                Text(String(format: "Avg %.2f", viewModel.stats.avg))
                Text(String(format: "P95 %.2f", viewModel.stats.p95))
            }
            .font(.subheadline.monospacedDigit())

            Toggle("Show raw records", isOn: $viewModel.showRawRecords)

            if viewModel.showRawRecords {
                List(viewModel.records) { row in
                    HStack {
                        Text(row.timestamp.formatted(date: .abbreviated, time: .standard))
                        Spacer()
                        Text(row.metricType)
                        Text(String(format: "%.2f", row.value))
                    }
                    .font(.caption.monospacedDigit())
                }
                .frame(minHeight: 160)
            }

            if viewModel.isExporting {
                ProgressView(value: viewModel.exportProgress)
            }
        }
        .padding(16)
        .onAppear { viewModel.reload() }
        .onChange(of: viewModel.metric) { _ in viewModel.reload() }
        .onChange(of: viewModel.preset) { _ in viewModel.reload() }
        .onChange(of: viewModel.customStart) { _ in viewModel.reload() }
        .onChange(of: viewModel.customEnd) { _ in viewModel.reload() }
    }
}
