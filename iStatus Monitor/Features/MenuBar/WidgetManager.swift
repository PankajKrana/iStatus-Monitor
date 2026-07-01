import Foundation
import Observation

// MARK: - Widget Manager

/// The presentation coordinator for the menu bar.
///
/// `WidgetManager` is the bridge between the three single-sources-of-truth and
/// the `MenuBarExtra` scene:
///
/// - `AppState`               — live metric data (read-only, never copied here)
/// - `WidgetConfigurationStore` — enabled state, order, display style, layout
/// - `WidgetRegistry`         — the catalogue of available widgets
///
/// It owns **no refresh engine**. The existing `SystemMonitorService → AppState`
/// pipeline is the only timer in the app. Every output below is a *computed*
/// property that reads `AppState` + the store + the registry; because all three
/// are `@Observable`, SwiftUI re-evaluates these (and re-renders the menu bar)
/// only when a value those computations actually touch changes — no polling, no
/// caching, no duplicate state.
@MainActor
@Observable
final class WidgetManager {

    /// Live metrics — the single source of truth. Held by reference; values are
    /// always read through it, never duplicated into the manager.
    let appState: AppState

    /// The catalogue of available widgets. The manager never constructs widgets;
    /// they are registered into the registry by the composition root.
    let registry: WidgetRegistry

    /// Menu bar configuration — enabled state, order, display style, layout.
    let configurationStore: WidgetConfigurationStore

    init(
        appState: AppState,
        registry: WidgetRegistry,
        configurationStore: WidgetConfigurationStore
    ) {
        self.appState = appState
        self.registry = registry
        self.configurationStore = configurationStore

        // Reconcile config with whatever is registered: add configs for new
        // widgets, drop configs for widgets that no longer exist.
        configurationStore.synchronize(withAvailableIDs: registry.availableIDs)
    }

    // MARK: Derived Outputs (recompute only when their inputs change)

    /// Enabled widgets paired with their configuration, in display order.
    /// Recomputes when the registry or the store's configurations change.
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

    /// A renderer bound to the current layout. The struct is cheap to create;
    /// reading `configurationStore.layout` registers the layout dependency so
    /// outputs recompute when the layout changes.
    private var renderer: MenuBarRenderer {
        MenuBarRenderer(layout: configurationStore.layout)
    }

    /// The enabled widgets in display order (without configuration).
    var enabledWidgets: [any MenuBarWidget] {
        enabledEntries.map(\.widget)
    }

    /// Structured segments for the view layer (carries text, SF Symbol, and
    /// severity so `MenuBarExtra`'s label can compose icons + colors).
    var menuBarSegments: [MenuBarSegment] {
        renderer.segments(for: enabledEntries, appState: appState)
    }

    /// Plain-text menu bar title — used for accessibility/tooltips and as a
    /// fallback label.
    var menuBarText: String {
        renderer.menuBarTitle(for: enabledEntries, appState: appState)
    }

    /// Severity-colored title, suitable for direct use as a `MenuBarExtra` label.
    var menuBarAttributedText: AttributedString {
        renderer.menuBarAttributedString(for: enabledEntries, appState: appState)
    }

    /// Whether anything is currently shown in the menu bar. Lets the scene fall
    /// back to a static glyph when no widgets are enabled.
    var hasEnabledWidgets: Bool {
        !configurationStore.enabledConfigurations().isEmpty
    }

    // MARK: Module Mode (one MenuBarExtra per widget)

    /// Compact (single combined item) vs. Module (one item per widget).
    /// Presentation only — never changes which widgets are enabled.
    var presentationMode: MenuBarPresentationMode {
        get { configurationStore.presentationMode }
        set { configurationStore.presentationMode = newValue }
    }

    /// Whether a widget is enabled in configuration. Drives a module item's
    /// `isInserted` together with `presentationMode == .module`.
    func isEnabled(_ id: String) -> Bool {
        configurationStore.configuration(for: id)?.isEnabled ?? false
    }

    /// The rendered segment for a single widget, for a module item's own label.
    /// Reuses the exact compact-mode formatting/severity via `MenuBarRenderer`.
    /// Returns `nil` when the widget is unknown or has no data yet.
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

    // MARK: Configuration Helpers (for the Settings UI)

    /// Reorder widgets — binds directly to a SwiftUI `List`'s `.onMove`.
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

    /// The current menu bar layout. Setting it persists through the store.
    var layout: MenuBarLayout {
        get { configurationStore.layout }
        set { configurationStore.layout = newValue }
    }

    /// Restore all widget configuration and layout to defaults.
    func resetToDefaults() {
        configurationStore.restoreDefaults()
    }
}
