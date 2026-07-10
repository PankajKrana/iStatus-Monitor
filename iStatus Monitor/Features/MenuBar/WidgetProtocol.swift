import Foundation

// MARK: - MenuBarWidget

/// A pure, stateless presentation unit for a single metric in the menu bar.
///
/// Widgets are value types (`struct`) that own **no** state and run **no**
/// timers. They are read-only views over `AppState`, which is the single source
/// of truth for live metric data (fed by `SystemMonitorService`). A widget's
/// only job is to turn the already-computed numbers in `AppState` into strings
/// and a severity level.
///
/// Because every method reads `AppState` (a `@MainActor @Observable` type), the
/// `AppState`-reading members are `@MainActor`. Reading those properties inside
/// SwiftUI's observation scope is what lets `MenuBarExtra` re-render *only* when
/// the values it actually displays change — no extra polling required.
///
/// Conformers are registered with `WidgetRegistry` and resolved by
/// `WidgetManager`; they are never hardcoded into the manager.
///
/// Not `Sendable`: every use site is `@MainActor` (registry, manager, renderer,
/// views), and the `@MainActor` requirements below would otherwise make each
/// widget's `Identifiable` conformance main-actor-isolated and unable to satisfy
/// a `Sendable` constraint.
protocol MenuBarWidget: Identifiable where ID == String {

    /// Stable identifier, e.g. `"cpu"`. Used to match a widget to its
    /// `WidgetConfiguration` and as the SwiftUI list identity for reordering.
    /// `nonisolated` so it satisfies `Identifiable.id` and is usable in keypaths
    /// (the module defaults to `@MainActor` isolation).
    nonisolated var id: String { get }

    /// Human-readable name shown in settings and detailed layouts, e.g. `"CPU"`.
    nonisolated var name: String { get }

    /// SF Symbol name used as the widget's icon, e.g. `"cpu"`.
    nonisolated var sfSymbol: String { get }

    /// Value at/above which the metric is considered a warning. For inverted
    /// metrics (e.g. battery, where *low* is bad) this is the lower bound; such
    /// widgets override `severity(from:)`.
    nonisolated var warningThreshold: Double { get }

    /// Value at/above which the metric is considered critical.
    nonisolated var criticalThreshold: Double { get }

    /// The raw numeric value used for threshold comparison (e.g. CPU percent,
    /// max temperature in °C). Returns `nil` when the underlying metric has no
    /// data yet (e.g. a Mac with no battery, GPU snapshot not ready).
    @MainActor func currentValue(from appState: AppState) -> Double?

    /// The string shown in the menu bar for this widget, e.g. `"15%"`.
    /// Returns a stable placeholder (e.g. `"--"`) when data is unavailable so
    /// the menu bar layout doesn't jump.
    @MainActor func formattedValue(from appState: AppState) -> String

    /// VoiceOver description, e.g. `"CPU: 15 percent"`.
    @MainActor func accessibilityLabel(from appState: AppState) -> String

    /// Severity bucket for coloring. Declared as a requirement (not extension-only)
    /// so widgets with inverted or non-threshold semantics — battery (low is bad),
    /// thermal (driven by `ThermalState`), network (always informational) — can
    /// override it and have the override dispatch correctly through
    /// `any MenuBarWidget`. A default "higher is worse" implementation is provided.
    @MainActor func severity(from appState: AppState) -> MetricSeverity
}

// MARK: - Default Behavior

extension MenuBarWidget {

    /// Default "higher is worse" severity, derived from the thresholds and the
    /// current value. Widgets whose semantics are inverted (battery) override
    /// this; widgets with no meaningful thresholds inherit `.normal`.
    @MainActor
    func severity(from appState: AppState) -> MetricSeverity {
        guard let value = currentValue(from: appState) else { return .normal }
        if value >= criticalThreshold { return .critical }
        if value >= warningThreshold { return .warning }
        return .normal
    }

    /// Whether this widget currently has data to display. Used by
    /// `WidgetManager` to decide if an enabled-but-dataless widget should be
    /// shown with a placeholder or skipped.
    @MainActor
    var hasDataDefault: Bool { false }

    @MainActor
    func hasData(in appState: AppState) -> Bool {
        currentValue(from: appState) != nil
    }
}
