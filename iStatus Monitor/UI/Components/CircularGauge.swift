import SwiftUI

/// An animated circular gauge for displaying percentage-based metrics.
/// Used for battery health, memory pressure, disk usage, etc.
struct CircularGauge: View {
    let value: Double
    let maximum: Double
    let color: Color
    let icon: String?
    let title: String?
    let label: String?
    var strokeWidth: CGFloat = 12

    init(
        value: Double,
        maximum: Double = 100,
        color: Color,
        icon: String? = nil,
        title: String? = nil,
        label: String? = nil,
        strokeWidth: CGFloat = 12
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
                    .stroke(Color.gray.opacity(0.2), lineWidth: strokeWidth)
                
                // Gradient progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(percentage))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.7), color]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(AppTheme.springAnimation, value: percentage)
                
                // Center content
                VStack(spacing: 2) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    
                    Text("\(Int(percentage * 100))%")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(color)
                    
                    if let label = label {
                        Text(label)
                            .font(.caption2)
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
