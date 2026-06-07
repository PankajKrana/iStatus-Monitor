import Foundation
import Observation

// MARK: - Widget Registry

/// The catalogue of widgets available to the menu bar.
///
/// `WidgetManager` resolves what it can show from this registry rather than
/// hardcoding the widget list, so new metrics can be added by registering a
/// `MenuBarWidget` — no edits to the manager required.
///
/// The registry holds **stateless presentation structs** only; it owns no live
/// metric data (that's `AppState`) and no user preferences (that's
/// `WidgetConfigurationStore`). It is `@MainActor` to match the rest of the
/// menu-bar layer and `@Observable` so SwiftUI reacts when widgets are
/// registered or removed.
@MainActor
@Observable
final class WidgetRegistry {

    /// All registered widgets, in registration order. `MenuBarWidget` is
    /// type-erased to `any` so heterogeneous widget structs coexist in one list.
    private(set) var availableWidgets: [any MenuBarWidget] = []

    init(widgets: [any MenuBarWidget] = []) {
        for widget in widgets {
            register(widget)
        }
    }

    // MARK: Registration

    /// Add a widget. Registering an `id` that already exists replaces the
    /// existing entry in place, keeping its position (idempotent registration).
    func register(_ widget: any MenuBarWidget) {
        if let index = availableWidgets.firstIndex(where: { $0.id == widget.id }) {
            availableWidgets[index] = widget
        } else {
            availableWidgets.append(widget)
        }
    }

    /// Remove a widget instance by its identity.
    func unregister(_ widget: any MenuBarWidget) {
        unregister(id: widget.id)
    }

    /// Remove a widget by `id`. No-op if the id isn't registered.
    func unregister(id: String) {
        availableWidgets.removeAll { $0.id == id }
    }

    // MARK: Lookup

    func widget(for id: String) -> (any MenuBarWidget)? {
        availableWidgets.first { $0.id == id }
    }

    /// All registered widget IDs, in order. Fed to
    /// `WidgetConfigurationStore.synchronize(withAvailableIDs:)` so config and
    /// registry stay reconciled.
    var availableIDs: [String] {
        availableWidgets.map(\.id)
    }
}
