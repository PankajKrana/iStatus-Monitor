import SwiftUI

/// An animated circular gauge for displaying percentage-based metrics.
/// Used for battery health, memory pressure, disk usage, etc.
struct CircularGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double
    let maximum: Double
    let color: Color
    let icon: String?
    let title: String?
    let label: String?
    var strokeWidth: CGFloat = 8

    init(
        value: Double,
        maximum: Double = 100,
        color: Color,
        icon: String? = nil,
        title: String? = nil,
        label: String? = nil,
        strokeWidth: CGFloat = 8
    ) {
        self.value = value
        self.maximum = maximum
        self.color = color
        self.icon = icon
        self.title = title
        self.label = label
        self.strokeWidth = strokeWidth
    }
    
    var percentage: Double {
        min(max(value / maximum, 0), 1)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if let title = title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            
            ZStack {
                // Background track
                Circle()
                    .stroke(.quaternary, lineWidth: strokeWidth)
                
                Circle()
                    .trim(from: 0, to: CGFloat(percentage))
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? .none : AppTheme.springAnimation, value: percentage)
                
                // Center content
                VStack(spacing: 2) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(color)
                    }
                    
                    Text("\(Int(percentage * 100))%")
                        .font(.title.monospacedDigit().weight(.light))
                        .foregroundStyle(color)
                    
                    if let label = label {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        CircularGauge(
            value: 68,
            color: .orange,
            icon: "cpu",
            title: "CPU Usage",
            label: "Active",
            strokeWidth: 10
        )
        .frame(width: 140, height: 180)
        
        CircularGauge(
            value: 70,
            color: .blue,
            icon: "memorychip",
            title: "Memory",
            label: "12.4 GB",
            strokeWidth: 10
        )
        .frame(width: 140, height: 180)
        
        CircularGauge(
            value: 45,
            color: .green,
            icon: "hdd",
            title: "Disk Usage",
            label: "450 GB",
            strokeWidth: 10
        )
        .frame(width: 140, height: 180)
    }
    .padding()
}
