import SwiftUI

/// The single severity model shared across the app: menu-bar widgets, dashboard
/// cards, status dots, and status badges all derive their "how bad is this"
/// state from this one type. Replaces the previously duplicated `WidgetSeverity`
/// and `StatusDot.Status`, and the bare `.normal/.warning/.critical` cases that
/// were scattered through the UI.
///
/// Presentation-only states (charging, full, "Retina", etc.) are deliberately
/// *not* modeled here — they live on `StatusBadge.Status` as separate cases, so
/// severity stays orthogonal to those labels.
///
/// `Comparable` so "worst severity wins" aggregations are a plain `max()` instead
/// of a hand-rolled rank mapping.
enum MetricSeverity: String, Sendable, Equatable, Comparable, CaseIterable {
    case normal
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .normal: 0
        case .warning: 1
        case .critical: 2
        }
    }

    static func < (lhs: MetricSeverity, rhs: MetricSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Traffic-light color for dashboard indicators (`StatusDot`, and the
    /// severity case of `StatusBadge`). The menu bar uses a different mapping
    /// (`menuBarColor(for:)`, primary/orange/red) because its severity tints text,
    /// not a status light — both are preserved intentionally.
    var indicatorColor: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    /// Icon for `StatusDot` (distinguishes state by shape as well as color).
    var indicatorIcon: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    /// Icon for `StatusBadge`'s severity case. Deliberately distinct from
    /// `indicatorIcon` (used by `StatusDot`) so each control keeps its
    /// established visual language.
    var severityBadgeIcon: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .critical: "xmark.circle.fill"
        }
    }
}
