import SwiftUI

/// A reusable status badge for showing system states like Charging, Discharging, etc.
struct StatusBadge: View {
    enum Status {
        case charging
        case discharging
        case full
        case severity(MetricSeverity)
        case custom(String, Color)
        
        var text: String {
            switch self {
            case .charging: return "Charging"
            case .discharging: return "Discharging"
            case .full: return "Full"
            case .severity(let severity): return severity.label
            case .custom(let text, _): return text
            }
        }
        
        var color: Color {
            switch self {
            case .charging, .full:
                return .green
            case .discharging:
                return .orange
            case .severity(let severity):
                return severity.indicatorColor
            case .custom(_, let color):
                return color
            }
        }
        
        var icon: String {
            switch self {
            case .charging: return "bolt.fill"
            case .discharging: return "battery.50"
            case .full: return "checkmark.circle.fill"
            case .severity(let severity): return severity.severityBadgeIcon
            case .custom: return "info.circle.fill"
            }
        }
    }
    
    let status: Status
    var size: CGFloat = 8
    
    var body: some View {
        Label(status.text, systemImage: status.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(Text(status.text))
            .accessibilityValue(Text(status.text))
    }
}

/// Inline status indicator that distinguishes state by icon as well as color.
struct StatusDot: View {
    let status: MetricSeverity
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: status.indicatorIcon)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(status.indicatorColor)
            .accessibilityLabel(status.label)
            .accessibilityValue(status.label)
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadge(status: .charging)
        StatusBadge(status: .discharging)
        StatusBadge(status: .full)
        StatusBadge(status: .severity(.normal))
        StatusBadge(status: .severity(.warning))
        StatusBadge(status: .severity(.critical))
        StatusBadge(status: .custom("Connected", .blue))

        HStack(spacing: 12) {
            StatusDot(status: .normal)
            StatusDot(status: .warning)
            StatusDot(status: .critical)
        }
    }
    .padding()
}
