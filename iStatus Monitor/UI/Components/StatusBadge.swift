import SwiftUI

/// A reusable status badge for showing system states like Charging, Discharging, etc.
struct StatusBadge: View {
    enum Status {
        case charging
        case discharging
        case full
        case normal
        case warning
        case critical
        case custom(String, Color)
        
        var text: String {
            switch self {
            case .charging: return "Charging"
            case .discharging: return "Discharging"
            case .full: return "Full"
            case .normal: return "Normal"
            case .warning: return "Warning"
            case .critical: return "Critical"
            case .custom(let text, _): return text
            }
        }
        
        var color: Color {
            switch self {
            case .charging, .full, .normal:
                return .green
            case .discharging:
                return .orange
            case .warning:
                return .yellow
            case .critical:
                return .red
            case .custom(_, let color):
                return color
            }
        }
        
        var icon: String {
            switch self {
            case .charging: return "bolt.fill"
            case .discharging: return "battery.50"
            case .full: return "checkmark.circle.fill"
            case .normal: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .critical: return "xmark.circle.fill"
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
            .accessibilityLabel(status.text)
    }
}

/// Inline status indicator that distinguishes state by icon as well as color.
struct StatusDot: View {
    enum Status {
        case good, warning, critical

        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .yellow
            case .critical: return .red
            }
        }

        var icon: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }

        var label: String {
            switch self {
            case .good: return "Normal"
            case .warning: return "Warning"
            case .critical: return "Critical"
            }
        }
    }

    let status: Status
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: status.icon)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(status.color)
            .accessibilityLabel(status.label)
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadge(status: .charging)
        StatusBadge(status: .discharging)
        StatusBadge(status: .full)
        StatusBadge(status: .normal)
        StatusBadge(status: .warning)
        StatusBadge(status: .critical)
        StatusBadge(status: .custom("Connected", .blue))
        
        HStack(spacing: 12) {
            StatusDot(status: .good)
            StatusDot(status: .warning)
            StatusDot(status: .critical)
        }
    }
    .padding()
}
