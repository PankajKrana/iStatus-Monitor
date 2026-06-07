import AppKit
import SwiftUI

// MARK: - Menu Bar Extra Scene

/// The native `MenuBarExtra` scene — the full replacement for the old
/// `NSStatusItem` + `NSTimer` system. It owns no status item, no timer, and no
/// refresh logic: the label and popover are plain SwiftUI views that read
/// `WidgetManager` / `AppState`, so Observation re-renders them automatically
/// whenever the displayed values change.
///
/// Dependencies are injected by the app's composition root; this scene never
/// constructs `AppState` or `WidgetManager`.
struct MenuBarExtraScene: Scene {
    let appState: AppState
    let widgetManager: WidgetManager

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(appState: appState, widgetManager: widgetManager)
        } label: {
            MenuBarLabelView(widgetManager: widgetManager)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Label

/// The menu bar title, built entirely from `widgetManager.menuBarSegments`.
/// Respects the active `MenuBarLayout` for spacing and separators, and renders
/// each segment's SF Symbol via `Image(systemName:)`.
///
/// Internal (not private) so the settings live-preview can render the exact same
/// label rather than reimplementing the layout logic.
struct MenuBarLabelView: View {
    let widgetManager: WidgetManager

    var body: some View {
        let segments = widgetManager.menuBarSegments
        let layout = widgetManager.layout

        if segments.isEmpty {
            // Nothing enabled / no data yet — show a neutral glyph so the menu
            // bar item remains clickable.
            Image(systemName: "gauge.with.dots.needle.33percent")
        } else {
            HStack(spacing: layout == .detailed ? 8 : 6) {
                ForEach(Array(segments.enumerated()), id: \.element.widgetId) { index, segment in
                    if layout == .separated, index > 0 {
                        Text("|").foregroundStyle(.secondary)
                    }
                    MenuBarSegmentView(segment: segment)
                }
            }
        }
    }
}

/// A single widget's icon + value in the menu bar label.
private struct MenuBarSegmentView: View {
    let segment: MenuBarSegment

    var body: some View {
        HStack(spacing: 3) {
            if segment.showsIcon {
                Image(systemName: segment.sfSymbol)
            }
            Text(segment.text)
        }
        .foregroundStyle(menuBarColor(for: segment.severity))
    }
}

// MARK: - Popover

/// A lightweight menu-bar popover listing the current metrics. It is *not* a
/// second dashboard — it reuses each widget's own formatting and reads values
/// straight from `AppState`. Only widgets with data are shown.
private struct MenuBarPopoverView: View {
    let appState: AppState
    let widgetManager: WidgetManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iStatus Monitor")
                .font(.headline)

            Divider()

            if availableWidgets.isEmpty {
                Text("Collecting metrics…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(availableWidgets, id: \.id) { widget in
                    MetricRow(widget: widget, appState: appState)
                }
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings…")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    /// All registered widgets that currently have data — the popover shows the
    /// full metric set (independent of which widgets are enabled in the bar).
    private var availableWidgets: [any MenuBarWidget] {
        widgetManager.registry.availableWidgets.filter { $0.hasData(in: appState) }
    }
}

/// One metric row: icon, name, and the widget's formatted value.
private struct MetricRow: View {
    let widget: any MenuBarWidget
    let appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: widget.sfSymbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(widget.name)
            Spacer(minLength: 16)
            Text(widget.formattedValue(from: appState))
                .monospacedDigit()
                .foregroundStyle(menuBarColor(for: widget.severity(from: appState)))
        }
    }
}

// MARK: - Severity Color

/// Maps a `WidgetSeverity` to a SwiftUI `Color` for the view layer. (The
/// renderer has its own copy for `AttributedString`; keeping `Color` out of
/// `WidgetSeverity` lets the protocol layer stay free of SwiftUI.)
private func menuBarColor(for severity: WidgetSeverity) -> Color {
    switch severity {
    case .normal: .primary
    case .warning: .orange
    case .critical: .red
    }
}
