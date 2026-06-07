import SwiftUI

// MARK: - Menu Bar Settings Panel

/// The menu bar customization UI, designed to drop into the existing
/// `SettingsView` as one more section (it is a plain `View`, not a new window).
///
/// All reads and writes flow through `WidgetManager`: the view never mutates
/// `WidgetConfigurationStore` directly, holds no duplicate state, and contains
/// no persistence or monitoring logic. Mutations go exclusively through
/// `toggleWidget`, `moveWidget`, `setDisplayStyle`, `layout`, and
/// `resetToDefaults`.
struct MenuBarSettingsPanel: View {
    @Bindable var widgetManager: WidgetManager

    var body: some View {
        Form {
            previewSection
            layoutSection
            widgetsSection
            resetSection
        }
        .formStyle(.grouped)
        .padding(16)
    }

    // MARK: Preview

    /// Live preview rendered with the *same* view as the real menu bar label
    /// (`MenuBarLabelView`), driven by `widgetManager.menuBarSegments`. No
    /// separate preview model — it reflects the current widgets and layout.
    private var previewSection: some View {
        Section("Preview") {
            HStack {
                Spacer()
                MenuBarLabelView(widgetManager: widgetManager)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Layout

    private var layoutSection: some View {
        Section("Layout") {
            Picker("Style", selection: $widgetManager.layout) {
                ForEach(MenuBarLayout.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }
            .pickerStyle(.segmented)

            Text(widgetManager.layout.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Widgets (enable / reorder / per-widget style)

    private var widgetsSection: some View {
        Section {
            ForEach(widgetManager.configurationStore.configurations) { configuration in
                WidgetRow(
                    configuration: configuration,
                    widget: widgetManager.registry.widget(for: configuration.widgetId),
                    isEnabled: enabledBinding(for: configuration.widgetId),
                    displayStyle: displayStyleBinding(for: configuration.widgetId)
                )
            }
            .onMove { source, destination in
                widgetManager.moveWidget(from: source, to: destination)
            }
        } header: {
            Text("Widgets")
        } footer: {
            Text("Drag to reorder. Disabled widgets are hidden from the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Reset

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults", role: .destructive) {
                widgetManager.resetToDefaults()
            }
        }
    }

    // MARK: Bindings (routed through WidgetManager)

    /// Reads live enabled state through the manager; writes via `toggleWidget`.
    private func enabledBinding(for id: String) -> Binding<Bool> {
        Binding {
            widgetManager.configurationStore.configuration(for: id)?.isEnabled ?? false
        } set: { _ in
            widgetManager.toggleWidget(id: id)
        }
    }

    /// Reads live display style through the manager; writes via `setDisplayStyle`.
    private func displayStyleBinding(for id: String) -> Binding<WidgetDisplayStyle> {
        Binding {
            widgetManager.configurationStore.configuration(for: id)?.displayStyle ?? .default
        } set: { newValue in
            widgetManager.setDisplayStyle(newValue, for: id)
        }
    }
}

// MARK: - Widget Row

/// One configurable widget: enable toggle (with icon + name) and a per-widget
/// display-style picker. Pure presentation — all state comes in via bindings.
private struct WidgetRow: View {
    let configuration: WidgetConfiguration
    let widget: (any MenuBarWidget)?
    @Binding var isEnabled: Bool
    @Binding var displayStyle: WidgetDisplayStyle

    var body: some View {
        HStack {
            Toggle(isOn: $isEnabled) {
                Label {
                    Text(widget?.name ?? configuration.widgetId)
                } icon: {
                    Image(systemName: widget?.sfSymbol ?? "questionmark.circle")
                }
            }

            Spacer(minLength: 16)

            Picker("Display style", selection: $displayStyle) {
                ForEach(WidgetDisplayStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150)
            .disabled(!isEnabled)
        }
    }
}
