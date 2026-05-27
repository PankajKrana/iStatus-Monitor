import Charts
import SwiftUI

struct RollingTimeSeriesChart<DataPoint: TimeSeriesDataPoint>: View {
    let points: [DataPoint]
    let windowSeconds: TimeInterval
    let yDomain: ClosedRange<Double>?
    let yLabelFormatter: (Double) -> String
    let accentColor: Color

    @State private var animatedPoints: [DataPoint] = []
    @State private var selectedPoint: DataPoint?

    init(
        points: [DataPoint],
        windowSeconds: TimeInterval = 60,
        yDomain: ClosedRange<Double>? = nil,
        yLabelFormatter: @escaping (Double) -> String,
        accentColor: Color
    ) {
        self.points = points
        self.windowSeconds = windowSeconds
        self.yDomain = yDomain
        self.yLabelFormatter = yLabelFormatter
        self.accentColor = accentColor
    }

    private var filteredPoints: [DataPoint] {
        guard let latest = points.last?.timestamp else { return [] }
        let cutoff = latest.addingTimeInterval(-windowSeconds)
        return points.filter { $0.timestamp >= cutoff }
    }

    private var isCollecting: Bool {
        guard let first = filteredPoints.first?.timestamp,
              let last = filteredPoints.last?.timestamp else {
            return true
        }
        return last.timeIntervalSince(first) < 5
    }

    var body: some View {
        chartBody
            .frame(height: 220)
            .contextMenu {
                Button("Copy as Image") {
                    ChartExportSupport.copyToPasteboard(view: chartBody, size: CGSize(width: 860, height: 320))
                }
            }
            .onAppear {
                animatedPoints = filteredPoints
            }
            .onChange(of: filteredPoints.map(\.timestamp)) { _ in
                withAnimation(.smooth(duration: 0.25)) {
                    animatedPoints = filteredPoints
                }
            }
    }

    @ViewBuilder
    private var chartBody: some View {
        if isCollecting {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.08))
                Text("collecting data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Chart {
                ForEach(Array(animatedPoints.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [accentColor.opacity(0.35), accentColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(accentColor)
                    .lineStyle(.init(lineWidth: 2))
                }

                if let selectedPoint {
                    RuleMark(x: .value("Cursor", selectedPoint.timestamp))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(.init(lineWidth: 1, dash: [4]))

                    PointMark(
                        x: .value("Cursor Time", selectedPoint.timestamp),
                        y: .value("Cursor Value", selectedPoint.value)
                    )
                    .symbolSize(50)
                    .foregroundStyle(accentColor)
                    .annotation(position: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(yLabelFormatter(selectedPoint.value))
                                .font(.caption2.weight(.semibold))
                            Text(selectedPoint.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .ifLet(yDomain) { view, domain in
                view.chartYScale(domain: domain)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .second, count: max(5, Int(windowSeconds / 6)))) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(relativeTimeLabel(for: date))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let y = value.as(Double.self) {
                            Text(yLabelFormatter(y))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let xPosition = drag.location.x - geo[proxy.plotAreaFrame].origin.x
                                    guard let date: Date = proxy.value(atX: xPosition) else { return }
                                    selectedPoint = nearestPoint(to: date, in: animatedPoints)
                                }
                                .onEnded { _ in
                                    selectedPoint = nil
                                }
                        )
                }
            }
        }
    }

    private func nearestPoint(to date: Date, in points: [DataPoint]) -> DataPoint? {
        points.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
    }

    private func relativeTimeLabel(for date: Date) -> String {
        guard let latest = animatedPoints.last?.timestamp else { return "now" }
        let seconds = Int(latest.timeIntervalSince(date))
        if seconds <= 2 { return "now" }
        return "\(seconds)s ago"
    }
}

private extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
