import SwiftUI

// MARK: - Advanced Menu Bar Settings View (Icon-based Display Configuration)

struct AdvancedMenuBarSettingsView: View {
    @Bindable var viewState: MenuBarViewState
    @State private var selectedStyle: MenuBarDisplayStyle

    init(viewState: MenuBarViewState) {
        self._viewState = Bindable(viewState)
        _selectedStyle = State(initialValue: viewState.displayStyle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Display Style Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Style")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Picker("Style", selection: $selectedStyle) {
                    ForEach(MenuBarDisplayStyle.allCases) { style in
                        VStack(alignment: .leading) {
                            Text(style.displayName)
                            Text(style.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedStyle) {
                    viewState.displayStyle = selectedStyle
                }

                // Style Preview
                PreviewMenuBarView(style: selectedStyle)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Divider()

            // MARK: - Metric Selection Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Visible Metrics")
                    .font(.headline)
                    .foregroundStyle(.primary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewState.configurations) { config in
                            MetricToggleRow(
                                config: config,
                                isEnabled: config.isEnabled,
                                action: {
                                    viewState.toggleMetric(config.metricType)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Divider()

            // MARK: - Appearance Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Toggle("Compact Mode", isOn: $viewState.compactMode)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Icon Size")
                        Spacer()
                        Text("\(Int(viewState.iconSize))px")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewState.iconSize, in: 10...18, step: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Text Size")
                        Spacer()
                        Text("\(Int(viewState.textSize))px")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewState.textSize, in: 8...14, step: 1)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Divider()

            // MARK: - Behavior Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Behavior")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Toggle("Hide in Full Screen", isOn: $viewState.hideWhenFullScreen)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Update Interval")
                        Spacer()
                        Text("\(String(format: "%.1f", viewState.updateInterval))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewState.updateInterval, in: 0.5...5.0, step: 0.5)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Metric Toggle Row

struct MetricToggleRow: View {
    let config: MenuBarMetricConfig
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: config.metricType.sfSymbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
                .foregroundStyle(isEnabled ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.metricType.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(config.metricType.sfSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in action() }
            ))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

// MARK: - Preview Menu Bar View

struct PreviewMenuBarView: View {
    let style: MenuBarDisplayStyle

    var previewValues: [MenuBarDisplayValue] {
        [
            MenuBarDisplayValue(
                metric: .cpu,
                percentage: 35,
                label: "CPU",
                secondaryValue: nil,
                color: .blue,
                isWarning: false,
                isCritical: false
            ),
            MenuBarDisplayValue(
                metric: .memory,
                percentage: 68,
                label: "RAM",
                secondaryValue: nil,
                color: .blue,
                isWarning: false,
                isCritical: false
            ),
            MenuBarDisplayValue(
                metric: .battery,
                percentage: 82,
                label: "Bat",
                secondaryValue: nil,
                color: .green,
                isWarning: false,
                isCritical: false
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(previewValues, id: \.metric.id) { value in
                    let config = MenuBarMetricConfig(
                        id: value.metric.id,
                        metricType: value.metric,
                        isEnabled: true
                    )
                    MenuBarItemView(
                        config: config,
                        value: value,
                        style: style,
                        iconSize: 12,
                        textSize: 9,
                        compactMode: false
                    )
                }

                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
        }
    }
}

// MARK: - Preview

#Preview {
    @State var viewState = MenuBarViewState()

    AdvancedMenuBarSettingsView(viewState: viewState)
        .frame(width: 400, height: 600)
}
