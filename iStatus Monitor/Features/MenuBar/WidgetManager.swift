import Foundation
import Observation

/// Coordinates menu bar presentation by combining live `AppState`, configuration, and the widget registry.
@MainActor
@Observable
final class WidgetManager {

    /// Live metrics source of truth; read by reference.
    let appState: AppState

    /// Catalogue of available widgets.
    let registry: WidgetRegistry

    /// Menu bar configuration (enabled state, order, style, layout).
    let configurationStore: WidgetConfigurationStore

    init(
        appState: AppState,
        registry: WidgetRegistry,
        configurationStore: WidgetConfigurationStore
    ) {
        self.appState = appState
        self.registry = registry
        self.configurationStore = configurationStore

        // Sync configuration with the current registry.
        configurationStore.synchronize(withAvailableIDs: registry.availableIDs)
    }

    // Derived outputs

    /// Enabled widgets with configuration in display order.
    private var enabledEntries: [MenuBarRenderer.Entry] {
        configurationStore.enabledConfigurations().compactMap { configuration in
            guard let widget = registry.widget(for: configuration.widgetId),
                  widget.hasData(in: appState)
            else {
                return nil
            }
            return (widget: widget, configuration: configuration)
        }
    }

    /// Renderer bound to the current layout.
    private var renderer: MenuBarRenderer {
        MenuBarRenderer(layout: configurationStore.layout)
    }

    /// The enabled widgets in display order (without configuration).
    var enabledWidgets: [any MenuBarWidget] {
        enabledEntries.map(\.widget)
    }

    /// Structured segments for composing the menu bar label.
    var menuBarSegments: [MenuBarSegment] {
        renderer.segments(for: enabledEntries, appState: appState)
    }

    /// Plain-text menu bar title.
    var menuBarText: String {
        renderer.menuBarTitle(for: enabledEntries, appState: appState)
    }

    /// Severity-colored title for direct use as a `MenuBarExtra` label.
    var menuBarAttributedText: AttributedString {
        renderer.menuBarAttributedString(for: enabledEntries, appState: appState)
    }

    /// Whether anything is currently shown in the menu bar.
    var hasEnabledWidgets: Bool {
        !configurationStore.enabledConfigurations().isEmpty
    }

    // Module Mode

    /// Compact (single item) vs. Module (one item per widget).
    var presentationMode: MenuBarPresentationMode {
        get { configurationStore.presentationMode }
        set { configurationStore.presentationMode = newValue }
    }

    /// Whether a widget is enabled.
    func isEnabled(_ id: String) -> Bool {
        configurationStore.configuration(for: id)?.isEnabled ?? false
    }

    /// Rendered segment for a single widget (or `nil`).
    func moduleSegment(for id: String) -> MenuBarSegment? {
        guard let configuration = configurationStore.configuration(for: id),
              let widget = registry.widget(for: id),
              widget.hasData(in: appState)
        else {
            return nil
        }
        let entry: MenuBarRenderer.Entry = (widget: widget, configuration: configuration)
        return renderer.segments(for: [entry], appState: appState).first
    }

    // Configuration Helpers

    /// Reorder widgets.
    func moveWidget(from source: IndexSet, to destination: Int) {
        configurationStore.move(fromOffsets: source, toOffset: destination)
    }

    /// Enable/disable a widget by id.
    func setWidgetEnabled(_ isEnabled: Bool, for id: String) {
        configurationStore.setEnabled(isEnabled, for: id)
    }

    /// Enable/disable a widget by id.
    func toggleWidget(id: String) {
        configurationStore.toggleEnabled(for: id)
    }

    /// Set a widget's per-segment display style.
    func setDisplayStyle(_ style: WidgetDisplayStyle, for id: String) {
        configurationStore.setDisplayStyle(style, for: id)
    }

    /// Current menu bar layout.
    var layout: MenuBarLayout {
        get { configurationStore.layout }
        set { configurationStore.layout = newValue }
    }

    /// Restore configuration and layout to defaults.
    func resetToDefaults() {
        configurationStore.restoreDefaults()
    }
}
