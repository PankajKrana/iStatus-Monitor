import Foundation
import Observation
import SwiftUI

// MARK: - Menu Bar Layout

/// How enabled widgets are arranged in the menu bar string.
///
/// - `compact`:   `CPU 15% RAM 70%`
/// - `separated`: `CPU 15% | RAM 70%`
/// - `detailed`:  `🖥 CPU 15%  💾 RAM 70%`
///
/// Consumed by `MenuBarRenderer`; persisted by `WidgetConfigurationStore`.
enum MenuBarLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case separated
    case detailed

    var id: String { rawValue }

    static let `default`: MenuBarLayout = .compact

    var displayName: String {
        switch self {
        case .compact: "Compact"
        case .separated: "Separated"
        case .detailed: "Detailed"
        }
    }

    var description: String {
        switch self {
        case .compact: "Values separated by spaces"
        case .separated: "Values divided by separators"
        case .detailed: "Icons, labels, and values"
        }
    }
}

// MARK: - Widget Display Style

/// Per-widget rendering format for its own segment of the menu bar string.
///
/// - `valueOnly`:     `15%`
/// - `labelAndValue`: `CPU 15%`
/// - `iconAndValue`:  `🖥 15%`
enum WidgetDisplayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case valueOnly
    case labelAndValue
    case iconAndValue

    var id: String { rawValue }

    static let `default`: WidgetDisplayStyle = .labelAndValue

    var displayName: String {
        switch self {
        case .valueOnly: "Value Only"
        case .labelAndValue: "Label + Value"
        case .iconAndValue: "Icon + Value"
        }
    }
}

// MARK: - Widget Configuration

/// User preferences for a single widget. Keyed to a widget by `widgetId`
/// (matching `MenuBarWidget.id`). Pure value type — holds no live metric data.
///
/// `order` mirrors the widget's index in the persisted array; the store keeps
/// the two in sync on every mutation so drag-to-reorder needs no extra model.
struct WidgetConfiguration: Codable, Equatable, Hashable, Sendable, Identifiable {
    let widgetId: String
    var isEnabled: Bool
    var order: Int
    var displayStyle: WidgetDisplayStyle

    /// `Identifiable` conformance for SwiftUI lists (drag-to-reorder).
    var id: String { widgetId }

    init(
        widgetId: String,
        isEnabled: Bool = false,
        order: Int = 0,
        displayStyle: WidgetDisplayStyle = .default
    ) {
        self.widgetId = widgetId
        self.isEnabled = isEnabled
        self.order = order
        self.displayStyle = displayStyle
    }
}

// MARK: - Widget Configuration Store

/// The single source of truth for **menu bar configuration** (the counterpart to
/// `AppState`, which is the single source of truth for live metrics).
///
/// Persists to `UserDefaults` as JSON — deliberately *not* SwiftData, which is
/// overkill for a small array of preferences. The store is generic: it knows
/// nothing about concrete widgets. Callers (`WidgetManager`) supply a seed of
/// default configurations and the set of currently-available widget IDs; the
/// store reconciles, persists, and exposes the ordered result to SwiftUI.
@MainActor
@Observable
final class WidgetConfigurationStore {

    /// Ordered configurations (index == intended display order). Mutated only
    /// through the methods below so `order` and persistence stay consistent.
    private(set) var configurations: [WidgetConfiguration]

    /// Selected menu bar layout. Persisted automatically.
    var layout: MenuBarLayout {
        didSet {
            guard layout != oldValue else { return }
            defaults.set(layout.rawValue, forKey: Keys.layout)
        }
    }

    private let defaults: UserDefaults

    /// Seed used on first launch and by `restoreDefaults()`. Provided by the
    /// caller so the store stays independent of concrete widgets.
    private let defaultConfigurations: [WidgetConfiguration]

    init(
        defaults: UserDefaults = .standard,
        defaultConfigurations: [WidgetConfiguration] = []
    ) {
        self.defaults = defaults
        self.defaultConfigurations = Self.normalized(defaultConfigurations)

        if let stored = Self.loadConfigurations(from: defaults), !stored.isEmpty {
            configurations = Self.normalized(stored)
        } else {
            configurations = self.defaultConfigurations
        }

        if let rawLayout = defaults.string(forKey: Keys.layout),
           let parsed = MenuBarLayout(rawValue: rawLayout) {
            layout = parsed
        } else {
            layout = .default
        }
    }

    // MARK: Reads

    /// Enabled configurations in display order.
    func enabledConfigurations() -> [WidgetConfiguration] {
        configurations.filter(\.isEnabled)
    }

    func configuration(for widgetId: String) -> WidgetConfiguration? {
        configurations.first { $0.widgetId == widgetId }
    }

    // MARK: Mutations

    func setEnabled(_ isEnabled: Bool, for widgetId: String) {
        guard let index = configurations.firstIndex(where: { $0.widgetId == widgetId }),
              configurations[index].isEnabled != isEnabled else { return }
        configurations[index].isEnabled = isEnabled
        persist()
    }

    func toggleEnabled(for widgetId: String) {
        guard let current = configuration(for: widgetId) else { return }
        setEnabled(!current.isEnabled, for: widgetId)
    }

    func setDisplayStyle(_ style: WidgetDisplayStyle, for widgetId: String) {
        guard let index = configurations.firstIndex(where: { $0.widgetId == widgetId }),
              configurations[index].displayStyle != style else { return }
        configurations[index].displayStyle = style
        persist()
    }

    /// Drag-to-reorder entry point — binds directly to SwiftUI `List`'s
    /// `.onMove(perform:)`. Renumbers `order` to stay contiguous.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        configurations.move(fromOffsets: source, toOffset: destination)
        reindex()
        persist()
    }

    /// Reset all configurations and layout to the seeded defaults.
    func restoreDefaults() {
        configurations = defaultConfigurations
        layout = .default
        persist()
    }

    /// Reconcile against the widgets currently registered: append defaults for
    /// newly-available IDs, drop configurations whose widget no longer exists.
    /// Keeps the store usable as widgets are added/removed without model edits.
    func synchronize(withAvailableIDs availableIDs: [String]) {
        let availableSet = Set(availableIDs)
        var result = configurations.filter { availableSet.contains($0.widgetId) }

        let knownIDs = Set(result.map(\.widgetId))
        for id in availableIDs where !knownIDs.contains(id) {
            let seed = defaultConfigurations.first { $0.widgetId == id }
            result.append(seed ?? WidgetConfiguration(widgetId: id))
        }

        let normalizedResult = Self.normalized(result)
        guard normalizedResult != configurations else { return }
        configurations = normalizedResult
        persist()
    }

    // MARK: Persistence

    private func persist() {
        reindex()
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        defaults.set(data, forKey: Keys.configurations)
    }

    private func reindex() {
        for index in configurations.indices where configurations[index].order != index {
            configurations[index].order = index
        }
    }

    private static func loadConfigurations(from defaults: UserDefaults) -> [WidgetConfiguration]? {
        guard let data = defaults.data(forKey: Keys.configurations) else { return nil }
        return try? JSONDecoder().decode([WidgetConfiguration].self, from: data)
    }

    /// Sort by stored `order`, then renumber to a contiguous 0..<n sequence.
    private static func normalized(_ configurations: [WidgetConfiguration]) -> [WidgetConfiguration] {
        configurations
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { index, config in
                var copy = config
                copy.order = index
                return copy
            }
    }

    private enum Keys {
        static let configurations = "menuBar.widgetConfigurations"
        static let layout = "menuBar.layout"
    }
}
