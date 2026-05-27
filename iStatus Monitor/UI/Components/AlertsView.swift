import SwiftUI

struct AlertsView: View {
    @Bindable var alertsStore: AlertsStore

    @State private var draftMetric: MetricType = .cpu
    @State private var draftCondition: Condition = .above
    @State private var draftThreshold: Double = 90
    @State private var draftCooldown: TimeInterval = 300
    @State private var draftLabel: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Alerts")
                    .font(.title3.weight(.semibold))

                ruleEditor

                ForEach(alertsStore.rules) { rule in
                    AlertRuleRow(rule: rule, alertsStore: alertsStore)
                }

                Divider()

                Text("History")
                    .font(.headline)

                if alertsStore.history.isEmpty {
                    Text("No alerts yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(alertsStore.history) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.ruleLabel)
                                .font(.subheadline.weight(.semibold))
                            Text("\(item.timestamp.formatted(date: .abbreviated, time: .standard)) • \(item.metric.title) • \(formatted(item.observedValue, metric: item.metric))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            alertsStore.refresh()
        }
    }

    private var ruleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Rule")
                .font(.headline)

            HStack {
                Picker("Metric", selection: $draftMetric) {
                    ForEach(MetricType.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }

                Picker("Condition", selection: $draftCondition) {
                    ForEach(Condition.allCases) { condition in
                        Text(condition.rawValue.capitalized).tag(condition)
                    }
                }
            }

            TextField("Label", text: $draftLabel)

            VStack(alignment: .leading, spacing: 4) {
                Text("Threshold: \(thresholdText)")
                Slider(value: $draftThreshold, in: draftMetric.defaultRange)
            }

            Picker("Cooldown", selection: $draftCooldown) {
                Text("1 min").tag(60.0)
                Text("5 min").tag(300.0)
                Text("10 min").tag(600.0)
                Text("30 min").tag(1800.0)
            }

            Button("Add Rule") {
                let label = draftLabel.isEmpty ? "\(draftMetric.title) \(draftCondition.rawValue) \(formatted(draftThreshold, metric: draftMetric))" : draftLabel
                alertsStore.saveRule(
                    AlertRule(
                        id: UUID(),
                        metric: draftMetric,
                        condition: draftCondition,
                        threshold: draftThreshold,
                        cooldown: draftCooldown,
                        isEnabled: true,
                        label: label
                    )
                )
                draftLabel = ""
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var thresholdText: String {
        formatted(draftThreshold, metric: draftMetric)
    }

    private func formatted(_ value: Double, metric: MetricType) -> String {
        switch metric {
        case .cpu, .memory, .battery: String(format: "%.0f%%", value)
        case .temperature: String(format: "%.1f°C", value)
        case .network: String(format: "%.0f KB/s", value)
        }
    }
}

private struct AlertRuleRow: View {
    @State private var rule: AlertRule
    @Bindable var alertsStore: AlertsStore

    init(rule: AlertRule, alertsStore: AlertsStore) {
        _rule = State(initialValue: rule)
        self.alertsStore = alertsStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(rule.label, isOn: $rule.isEnabled)
                    .onChange(of: rule.isEnabled) { _ in
                        alertsStore.saveRule(rule)
                    }

                Spacer()

                Button("Test Alert") {
                    alertsStore.testRule(id: rule.id)
                }

                Button(role: .destructive) {
                    alertsStore.deleteRule(id: rule.id)
                } label: {
                    Image(systemName: "trash")
                }
            }

            HStack {
                Picker("Metric", selection: $rule.metric) {
                    ForEach(MetricType.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }

                Picker("Condition", selection: $rule.condition) {
                    ForEach(Condition.allCases) { condition in
                        Text(condition.rawValue.capitalized).tag(condition)
                    }
                }
            }
            .onChange(of: rule.metric) { _ in alertsStore.saveRule(rule) }
            .onChange(of: rule.condition) { _ in alertsStore.saveRule(rule) }

            VStack(alignment: .leading) {
                Text("Threshold: \(thresholdText)")
                Slider(value: $rule.threshold, in: rule.metric.defaultRange)
                    .onChange(of: rule.threshold) { _ in alertsStore.saveRule(rule) }
            }

            Picker("Cooldown", selection: $rule.cooldown) {
                Text("1m").tag(60.0)
                Text("5m").tag(300.0)
                Text("10m").tag(600.0)
                Text("30m").tag(1800.0)
            }
            .onChange(of: rule.cooldown) { _ in alertsStore.saveRule(rule) }
        }
        .padding(12)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var thresholdText: String {
        switch rule.metric {
        case .cpu, .memory, .battery: String(format: "%.0f%%", rule.threshold)
        case .temperature: String(format: "%.1f°C", rule.threshold)
        case .network: String(format: "%.0f KB/s", rule.threshold)
        }
    }
}
