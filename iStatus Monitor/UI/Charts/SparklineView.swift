import Charts
import SwiftUI

struct SparklineView: View {
    let values: [Double]
    let color: Color

    @State private var selectedValue: Double?

    init(values: [Double], color: Color = .accentColor) {
        self.values = values
        self.color = color
    }

    private var points: [ScalarPoint] {
        let now = Date()
        return values.enumerated().map { idx, value in
            ScalarPoint(timestamp: now.addingTimeInterval(Double(idx - values.count)), value: value)
        }
    }

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("T", point.timestamp), y: .value("V", point.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)

            if let selectedValue {
                RuleMark(y: .value("S", selectedValue))
                    .foregroundStyle(color.opacity(0.35))
            }
        }
        .frame(height: 40)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let x = drag.location.x - geo[proxy.plotAreaFrame].origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                let nearest = points.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
                                selectedValue = nearest?.value
                            }
                            .onEnded { _ in
                                selectedValue = nil
                            }
                    )
            }
        }
        .contextMenu {
            Button("Copy as Image") {
                ChartExportSupport.copyToPasteboard(view: self, size: CGSize(width: 300, height: 80))
            }
        }
    }
}
