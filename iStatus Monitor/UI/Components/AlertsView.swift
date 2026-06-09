import SwiftUI

// MARK: - SwiftUI visual mapping

extension AlertSeverity {
    var color: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// Semantic accent color for a metric, reusing the app-wide palette.
func metricColor(_ metric: MetricType) -> Color {
    switch metric {
    case .cpu: AppTheme.cpuColor
    case .memory: AppTheme.ramColor
    case .temperature: AppTheme.temperatureColor
    case .battery: AppTheme.batteryColor
    case .network: AppTheme.networkColor
    }
}

func formattedMetric(_ value: Double, metric: MetricType) -> String {
    switch metric {
    case .cpu, .memory, .battery: String(format: "%.0f%%", value)
    case .temperature: String(format: "%.1f°C", value)
    case .network: String(format: "%.0f KB/s", value)
    }
}

private let sustainedOptions: [(label: String, value: TimeInterval)] = [
    ("Off", 0), ("5s", 5), ("10s", 10), ("30s", 30), ("60s", 60)
]

private let cooldownOptions: [(label: String, value: TimeInterval)] = [
    ("1 min", 60), ("5 min", 300), ("10 min", 600), ("30 min", 1800)
]

private func effectiveSustainedOptions(current: TimeInterval) -> [(label: String, value: TimeInterval)] {
    var opts = sustainedOptions
    if !opts.contains(where: { $0.value == current }) {
        let customLabel = String(format: "Custom (%.0fs)", current)
        opts.append((customLabel, current))
    }
    return opts
}

private func effectiveCooldownOptions(current: TimeInterval) -> [(label: String, value: TimeInterval)] {
    var opts = cooldownOptions
    if !opts.contains(where: { $0.value == current }) {
        // Display in minutes with up to one decimal if needed.
        let minutes = current / 60.0
        let formatted: String
        if minutes == floor(minutes) {
            formatted = String(format: "Custom (%.0f min)", minutes)
        } else {
            formatted = String(format: "Custom (%.1f min)", minutes)
        }
        opts.append((formatted, current))
    }
    return opts
}

// MARK: - AlertsView

struct AlertsView: View {
    @Bindable var alertsStore: AlertsStore

    private enum Segment: String, CaseIterable, Identifiable {
        case rules = "Rules"
        case history = "History"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .rules
    @State private var search = ""
    @State private var severityFilter: AlertSeverity?
    @State private var sortNewestFirst = true
    @State private var selectedEntryID: AlertHistoryEntry.ID?
    @State private var showingAddRule = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if alertsStore.notificationsDenied {
                notificationsDisabledBanner
            }
            Divider()
            Group {
                switch segment {
                case .rules: rulesTab
                case .history: historyTab
                }
            }
        }
        .background(.background)
        .onAppear { alertsStore.refresh() }
        .sheet(isPresented: $showingAddRule) {
            AddRuleSheet { rule in alertsStore.saveRule(rule) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            Spacer()

            if segment == .rules {
                Button {
                    showingAddRule = true
                } label: {
                    Label("New Rule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            } else if !alertsStore.history.isEmpty {
                Button(role: .destructive) {
                    alertsStore.clearHistory()
                    selectedEntryID = nil
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var notificationsDisabledBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Notifications are turned off")
                    .font(.subheadline.weight(.semibold))
                Text("Alerts are recorded but won't be delivered until you enable notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { alertsStore.requestNotificationAccess() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Rules tab

    private var rulesTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if alertsStore.rules.isEmpty {
                    EmptyStateView(
                        symbol: "bell.badge",
                        title: "No Alert Rules",
                        message: "Create a rule to get notified when a metric crosses a threshold."
                    ) {
                        Button {
                            showingAddRule = true
                        } label: {
                            Label("Add Your First Rule", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(alertsStore.rules) { rule in
                        AlertRuleCard(rule: rule, alertsStore: alertsStore)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: History tab

    private var filteredHistory: [AlertHistoryEntry] {
        var items = alertsStore.history
        if let severityFilter {
            items = items.filter { $0.severity == severityFilter }
        }
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = search.lowercased()
            items = items.filter {
                $0.ruleLabel.lowercased().contains(q) || $0.metric.title.lowercased().contains(q)
            }
        }
        return items.sorted {
            sortNewestFirst ? $0.timestamp > $1.timestamp : $0.timestamp < $1.timestamp
        }
    }

    private var groupedHistory: [(day: Date, entries: [AlertHistoryEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredHistory) { calendar.startOfDay(for: $0.timestamp) }
        return groups
            .map { (day: $0.key, entries: $0.value) }
            .sorted { sortNewestFirst ? $0.day > $1.day : $0.day < $1.day }
    }

    private var historyTab: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                historyToolbar
                Divider()
                if alertsStore.history.isEmpty {
                    EmptyStateView(
                        symbol: "checkmark.seal.fill",
                        title: "All Clear",
                        message: "No alerts have fired. Triggered alerts will appear here."
                    )
                    .frame(maxHeight: .infinity)
                } else if filteredHistory.isEmpty {
                    EmptyStateView(
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "No Matches",
                        message: "No alerts match your current filters."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    historyList
                }
            }
            .frame(maxWidth: .infinity)

            if let id = selectedEntryID,
               let entry = alertsStore.history.first(where: { $0.id == id }) {
                Divider()
                AlertDetailView(entry: entry)
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(AppTheme.springAnimation, value: selectedEntryID)
    }

    private var historyToolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search alerts", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                SeverityFilterChip(title: "All", count: alertsStore.history.count,
                                   color: .secondary, isSelected: severityFilter == nil) {
                    severityFilter = nil
                }
                ForEach(AlertSeverity.allCases.reversed()) { sev in
                    SeverityFilterChip(
                        title: sev.title,
                        count: alertsStore.history.filter { $0.severity == sev }.count,
                        color: sev.color,
                        isSelected: severityFilter == sev
                    ) {
                        severityFilter = (severityFilter == sev) ? nil : sev
                    }
                }
                Spacer()
                Button {
                    sortNewestFirst.toggle()
                } label: {
                    Image(systemName: sortNewestFirst ? "arrow.down" : "arrow.up")
                    Text(sortNewestFirst ? "Newest" : "Oldest")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var historyList: some View {
        List(selection: $selectedEntryID) {
            ForEach(groupedHistory, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        AlertHistoryRow(entry: entry)
                            .tag(entry.id)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(dayHeader(group.day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func dayHeader(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .complete, time: .omitted)
    }
}

// MARK: - Severity filter chip

private struct SeverityFilterChip: View {
    let title: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.medium))
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                isSelected ? color.opacity(0.18) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(isSelected ? color.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History row

private struct AlertHistoryRow: View {
    let entry: AlertHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.severity.systemImage)
                .foregroundStyle(entry.severity.color)
                .font(.system(size: 15))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.ruleLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(entry.metric.title, systemImage: entry.metric.systemImage)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(metricColor(entry.metric))
                    Text("•").foregroundStyle(.tertiary)
                    Text(formattedMetric(entry.observedValue, metric: entry.metric))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.severity.title) alert: \(entry.ruleLabel), \(entry.metric.title) at \(formattedMetric(entry.observedValue, metric: entry.metric))")
    }
}

// MARK: - Detail inspector

private struct AlertDetailView: View {
    let entry: AlertHistoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: entry.severity.systemImage)
                        .font(.title2)
                        .foregroundStyle(entry.severity.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.severity.title)
                            .font(.headline)
                            .foregroundStyle(entry.severity.color)
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                detailRow("Rule", entry.ruleLabel)
                detailRow("Metric", entry.metric.title, color: metricColor(entry.metric),
                          symbol: entry.metric.systemImage)
                detailRow("Observed", formattedMetric(entry.observedValue, metric: entry.metric))
                if let threshold = entry.threshold, let condition = entry.condition {
                    detailRow("Threshold",
                              "\(condition == .above ? "Above" : "Below") \(formattedMetric(threshold, metric: entry.metric))")
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.3))
    }

    private func detailRow(_ label: String, _ value: String, color: Color? = nil, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).foregroundStyle(color ?? .primary) }
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color ?? .primary)
            }
        }
    }
}

// MARK: - Rule card

private struct AlertRuleCard: View {
    @State private var rule: AlertRule
    @Bindable var alertsStore: AlertsStore

    init(rule: AlertRule, alertsStore: AlertsStore) {
        _rule = State(initialValue: rule)
        self.alertsStore = alertsStore
    }

    private var summary: String {
        let cond = rule.condition == .above ? "above" : "below"
        var s = "\(cond) \(formattedMetric(rule.threshold, metric: rule.metric))"
        if rule.sustainedFor > 0 { s += " for \(Int(rule.sustainedFor))s" }
        return s
    }

    var body: some View {
        GlassCard(material: .ultraThin, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(metricColor(rule.metric).opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: rule.metric.systemImage)
                            .foregroundStyle(metricColor(rule.metric))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.label.isEmpty ? rule.metric.title : rule.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $rule.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: rule.isEnabled) { _, _ in save() }
                        .accessibilityLabel("Enable \(rule.label)")
                }

                HStack(spacing: 10) {
                    Picker("Metric", selection: $rule.metric) {
                        ForEach(MetricType.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: rule.metric) { _, _ in save() }

                    Picker("Condition", selection: $rule.condition) {
                        Text("Above").tag(Condition.above)
                        Text("Below").tag(Condition.below)
                    }
                    .onChange(of: rule.condition) { _, _ in save() }
                }
                .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Threshold: \(formattedMetric(rule.threshold, metric: rule.metric))")
                        .font(.caption)
                    Slider(value: $rule.threshold, in: rule.metric.defaultRange) { editing in
                        if !editing { save() }
                    }
                    .tint(metricColor(rule.metric))
                }

                HStack(spacing: 10) {
                    Picker("Sustain", selection: $rule.sustainedFor) {
                        ForEach(effectiveSustainedOptions(current: rule.sustainedFor), id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .onChange(of: rule.sustainedFor) { _, _ in save() }

                    Picker("Cooldown", selection: $rule.cooldown) {
                        ForEach(effectiveCooldownOptions(current: rule.cooldown), id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .onChange(of: rule.cooldown) { _, _ in save() }
                }
                .controlSize(.small)

                HStack {
                    Button {
                        alertsStore.testRule(id: rule.id)
                    } label: {
                        Label("Test", systemImage: "bell.and.waves.left.and.right")
                    }
                    .controlSize(.small)

                    Spacer()

                    Button(role: .destructive) {
                        alertsStore.deleteRule(id: rule.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func save() { alertsStore.saveRule(rule) }
}

// MARK: - Add rule sheet

private struct AddRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (AlertRule) -> Void

    @State private var metric: MetricType = .cpu
    @State private var condition: Condition = .above
    @State private var threshold: Double = 90
    @State private var sustainedFor: TimeInterval = 0
    @State private var cooldown: TimeInterval = 300
    @State private var label: String = ""

    private var previewText: String {
        let cond = condition == .above ? "rises above" : "drops below"
        var s = "Alert when \(metric.title) \(cond) \(formattedMetric(threshold, metric: metric))"
        if sustainedFor > 0 { s += " for \(Int(sustainedFor)) seconds" }
        return s + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Alert Rule").font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(16)
            Divider()

            Form {
                Section {
                    Picker("Metric", selection: $metric) {
                        ForEach(MetricType.allCases) {
                            Label($0.title, systemImage: $0.systemImage).tag($0)
                        }
                    }
                    .onChange(of: metric) { _, newValue in
                        threshold = min(max(threshold, newValue.defaultRange.lowerBound), newValue.defaultRange.upperBound)
                    }
                    Picker("Condition", selection: $condition) {
                        Text("Above").tag(Condition.above)
                        Text("Below").tag(Condition.below)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Threshold: \(formattedMetric(threshold, metric: metric))")
                            .font(.callout)
                        Slider(value: $threshold, in: metric.defaultRange)
                            .tint(metricColor(metric))
                    }
                    Picker("Sustain for", selection: $sustainedFor) {
                        ForEach(sustainedOptions, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    Picker("Cooldown", selection: $cooldown) {
                        ForEach(cooldownOptions, id: \.value) { Text($0.label).tag($0.value) }
                    }
                }

                Section {
                    TextField("Label (optional)", text: $label)
                } footer: {
                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Rule") {
                    let finalLabel = label.isEmpty
                        ? "\(metric.title) \(condition.rawValue) \(formattedMetric(threshold, metric: metric))"
                        : label
                    onSave(AlertRule(
                        id: UUID(),
                        metric: metric,
                        condition: condition,
                        threshold: threshold,
                        cooldown: cooldown,
                        isEnabled: true,
                        label: finalLabel,
                        sustainedFor: sustainedFor
                    ))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 440, height: 520)
    }
}

// MARK: - Empty state

private struct EmptyStateView<Accessory: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var accessory: () -> Accessory

    init(symbol: String, title: String, message: String,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            accessory()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
