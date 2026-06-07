import Foundation
import SwiftUI

// MARK: - Menu Bar Segment

/// One widget's rendered contribution to the menu bar, as structured data.
///
/// The renderer produces these so two consumers can share one formatting pass:
/// the pure `String`/`AttributedString` outputs (for the label text and
/// accessibility), and the view layer (`MenuBarExtraScene`), which composes the
/// actual SF Symbol icons via `Text`/`Image` — something a `String` cannot carry.
struct MenuBarSegment: Equatable, Sendable {
    let widgetId: String
    /// The textual part, e.g. `"CPU 15%"` or `"15%"` depending on display style.
    let text: String
    /// SF Symbol name for the view layer to render when `showsIcon` is true.
    let sfSymbol: String
    /// Whether this segment's display style / layout calls for an icon.
    let showsIcon: Bool
    /// Severity for coloring (text in attributed output, icon in the view layer).
    let severity: WidgetSeverity
}

// MARK: - Menu Bar Renderer

/// Pure formatting for the menu bar. No SwiftUI views, no image drawing, no
/// state, no side effects — given the enabled widgets, the current `AppState`,
/// and a `MenuBarLayout`, it returns strings/segments. Keeping it pure is what
/// lets the menu bar stay near-zero-cost: it runs only when `WidgetManager`'s
/// observed values actually change.
struct MenuBarRenderer {

    /// An enabled widget paired with its user configuration.
    typealias Entry = (widget: any MenuBarWidget, configuration: WidgetConfiguration)

    var layout: MenuBarLayout = .default

    // MARK: Segments

    /// Build the structured segments for the given entries, in order.
    @MainActor
    func segments(for entries: [Entry], appState: AppState) -> [MenuBarSegment] {
        entries.map { entry in
            let style = entry.configuration.displayStyle
            let includeLabel = style == .labelAndValue || layout == .detailed
            let includeIcon = style == .iconAndValue || layout == .detailed

            let value = entry.widget.formattedValue(from: appState)
            let text = includeLabel ? "\(entry.widget.name) \(value)" : value

            return MenuBarSegment(
                widgetId: entry.widget.id,
                text: text,
                sfSymbol: entry.widget.sfSymbol,
                showsIcon: includeIcon,
                severity: entry.widget.severity(from: appState)
            )
        }
    }

    // MARK: String Output

    /// Plain-text title for the menu bar / tooltips / accessibility. Icons are
    /// omitted here by design — they are a view-layer concern. Returns an empty
    /// string when nothing is enabled (caller decides on a fallback glyph).
    @MainActor
    func menuBarTitle(for entries: [Entry], appState: AppState) -> String {
        joined(segments(for: entries, appState: appState).map(\.text))
    }

    /// Colored title: same composition as `menuBarTitle`, with each segment
    /// tinted by its severity. This is what `WidgetManager` exposes as the
    /// observed label value.
    @MainActor
    func menuBarAttributedString(for entries: [Entry], appState: AppState) -> AttributedString {
        let segments = segments(for: entries, appState: appState)
        let separator = AttributedString(separatorString)

        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { result += separator }

            var piece = AttributedString(segment.text)
            piece.foregroundColor = color(for: segment.severity)
            result += piece
        }
        return result
    }

    // MARK: Layout Helpers

    /// The string that divides segments for the current layout.
    private var separatorString: String {
        switch layout {
        case .compact: " "
        case .separated: " | "
        case .detailed: "  "
        }
    }

    private func joined(_ pieces: [String]) -> String {
        pieces.filter { !$0.isEmpty }.joined(separator: separatorString)
    }

    /// Maps severity to a color. Lives here, not in widgets, so `MenuBarWidget`
    /// stays free of SwiftUI/`Color`.
    private func color(for severity: WidgetSeverity) -> Color {
        switch severity {
        case .normal: .primary
        case .warning: .orange
        case .critical: .red
        }
    }
}
