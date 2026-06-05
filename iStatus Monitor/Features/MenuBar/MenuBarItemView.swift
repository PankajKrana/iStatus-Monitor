import SwiftUI

// MARK: - Menu Bar Item View

struct MenuBarItemView: View {
    let config: MenuBarMetricConfig
    let value: MenuBarDisplayValue
    let style: MenuBarDisplayStyle
    let iconSize: CGFloat
    let textSize: CGFloat
    let compactMode: Bool

    var body: some View {
        HStack(spacing: compactMode ? 2 : 4) {
            // Icon with dynamic coloring
            Image(systemName: getSymbolName())
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(getIconColor())
                .frame(width: iconSize + 2, height: iconSize + 2, alignment: .center)
                .accessibilityLabel("Icon")

            // Content based on style
            switch style {
            case .iconPercentage:
                Text(value.formattedValue)
                    .font(.system(size: textSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)

            case .iconLabelPercentage:
                VStack(alignment: .leading, spacing: 0) {
                    Text(config.label)
                        .font(.system(size: textSize - 1, weight: .semibold, design: .default))
                    Text(value.formattedValue)
                        .font(.system(size: textSize, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.primary)

            case .iconOnly:
                EmptyView()

            case .compactIconValue:
                Text(value.formattedValue)
                    .font(.system(size: textSize - 0.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .lineLimit(1)
        .help(value.accessibilityLabel)
    }

    private func getSymbolName() -> String {
        switch value.metric {
        case .battery:
            MenuBarSymbol(value.metric.sfSymbol)
                .getBatterySymbol(for: value.percentage)
        case .temperature:
            MenuBarSymbol(value.metric.sfSymbol)
                .getTemperatureSymbol(celsius: value.percentage)
        default:
            value.metric.sfSymbol
        }
    }

    private func getIconColor() -> Color {
        if value.isCritical {
            return .red
        } else if value.isWarning {
            return .orange
        }
        return .primary
    }
}

// MARK: - Menu Bar Stack View

struct MenuBarStackView: View {
    let values: [MenuBarDisplayValue]
    let style: MenuBarDisplayStyle
    let iconSize: CGFloat
    let textSize: CGFloat
    let compactMode: Bool
    let configs: [MenuBarMetricConfig]

    var body: some View {
        HStack(spacing: compactMode ? 6 : 12) {
            ForEach(values, id: \.metric.id) { value in
                if let config = configs.first(where: { $0.metricType == value.metric }) {
                    MenuBarItemView(
                        config: config,
                        value: value,
                        style: style,
                        iconSize: iconSize,
                        textSize: textSize,
                        compactMode: compactMode
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, compactMode ? 6 : 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Menu Bar Item Style Preview

#Preview {
    VStack(spacing: 16) {
        Text("Icon + % Style")
            .font(.headline)

        MenuBarItemView(
            config: MenuBarMetricConfig(id: "cpu", metricType: .cpu, isEnabled: true),
            value: MenuBarDisplayValue(
                metric: .cpu,
                percentage: 45,
                label: "CPU",
                secondaryValue: nil,
                color: .blue,
                isWarning: false,
                isCritical: false
            ),
            style: .iconPercentage,
            iconSize: 14,
            textSize: 10,
            compactMode: false
        )
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)

        Divider()

        Text("Icon + Label + % Style")
            .font(.headline)

        MenuBarItemView(
            config: MenuBarMetricConfig(id: "memory", metricType: .memory, isEnabled: true),
            value: MenuBarDisplayValue(
                metric: .memory,
                percentage: 72,
                label: "RAM",
                secondaryValue: nil,
                color: .blue,
                isWarning: true,
                isCritical: false
            ),
            style: .iconLabelPercentage,
            iconSize: 14,
            textSize: 10,
            compactMode: false
        )
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)

        Divider()

        Text("All Styles Combined")
            .font(.headline)

        VStack(spacing: 8) {
            MenuBarStackView(
                values: [
                    MenuBarDisplayValue(metric: .cpu, percentage: 35, label: "CPU", secondaryValue: nil, color: .blue, isWarning: false, isCritical: false),
                    MenuBarDisplayValue(metric: .memory, percentage: 68, label: "RAM", secondaryValue: nil, color: .blue, isWarning: false, isCritical: false),
                    MenuBarDisplayValue(metric: .battery, percentage: 82, label: "Bat", secondaryValue: nil, color: .green, isWarning: false, isCritical: false),
                ],
                style: .iconPercentage,
                iconSize: 14,
                textSize: 10,
                compactMode: false,
                configs: MenuBarMetricConfig.defaultConfigurations()
            )

            MenuBarStackView(
                values: [
                    MenuBarDisplayValue(metric: .cpu, percentage: 35, label: "CPU", secondaryValue: nil, color: .blue, isWarning: false, isCritical: false),
                    MenuBarDisplayValue(metric: .memory, percentage: 68, label: "RAM", secondaryValue: nil, color: .blue, isWarning: false, isCritical: false),
                ],
                style: .compactIconValue,
                iconSize: 12,
                textSize: 9,
                compactMode: true,
                configs: MenuBarMetricConfig.defaultConfigurations()
            )
        }
    }
    .padding()
}
