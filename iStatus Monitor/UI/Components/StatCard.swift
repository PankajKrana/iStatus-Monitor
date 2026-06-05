import SwiftUI

/// A stat card showing a metric with trend graph, status indicator, and mini statistics.
struct StatCard: View {
    let title: String
    let value: String
    let unit: String?
    let color: Color
    let trend: [Double]
    let icon: String?
    let details: [(label: String, value: String)]?
    var isCompact: Bool = false
    
    init(
        title: String,
        value: String,
        unit: String? = nil,
        color: Color,
        trend: [Double] = [],
        icon: String? = nil,
        details: [(label: String, value: String)]? = nil,
        isCompact: Bool = false
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.color = color
        self.trend = trend
        self.icon = icon
        self.details = details
        self.isCompact = isCompact
    }
    
    var body: some View {
        GlassCard(material: .thin, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                // Header with title and icon
                HStack(spacing: 8) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Status indicator
                    Circle()
                        .fill(color.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
                
                if isCompact {
                    compactLayout
                } else {
                    expandedLayout
                }
            }
        }
    }
    
    @ViewBuilder
    private var compactLayout: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(color)
                    
                    if let unit = unit {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if !trend.isEmpty {
                SparklineChart(data: trend, color: color)
                    .frame(width: 40, height: 24)
            }
        }
    }
    
    @ViewBuilder
    private var expandedLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(color)
                    
                    if let unit = unit {
                        Text(unit)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let details = details {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(details.indices, id: \.self) { index in
                            let detail = details[index]
                            HStack(spacing: 4) {
                                Text(detail.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(detail.value)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            if !trend.isEmpty {
                SparklineChart(data: trend, color: color)
                    .frame(width: 60, height: 32)
            }
        }
    }
}

// MARK: - Sparkline Chart Component
struct SparklineChart: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        Canvas { context, size in
            guard !data.isEmpty else { return }
            
            let min = data.min() ?? 0
            let maxValue = data.max() ?? 100
            let range = maxValue - min > 0 ? maxValue - min : 1
            
            var path = Path()
            for (index, value) in data.enumerated() {
                let x = CGFloat(index) / CGFloat(Swift.max(data.count - 1, 1)) * size.width
                let normalizedY = (value - min) / range
                let y = size.height * (1 - normalizedY)
                
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            context.stroke(path, with: .color(color), lineWidth: 2)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        StatCard(
            title: "CPU",
            value: "68",
            unit: "%",
            color: .orange,
            trend: [20, 35, 42, 55, 68, 62, 58],
            icon: "cpu"
        )
        
        StatCard(
            title: "Memory",
            value: "12.4",
            unit: "GB",
            color: .blue,
            trend: [5, 8, 10, 12, 11, 12.4],
            icon: "memorychip",
            details: [
                ("App", "8GB"),
                ("Cache", "2GB")
            ],
            isCompact: false
        )
    }
    .padding()
}
