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
        // Compact mode: the original single combined item.
        MenuBarExtra(isInserted: compactInsertedBinding) {
            MenuBarPopoverView(appState: appState, widgetManager: widgetManager)
        } label: {
            // The menu bar label is always present in an LSUIElement app, making
            // it the reliable host for the "open dashboard from a notification
            // tap" bridge (AppKit cannot open a SwiftUI WindowGroup directly).
            MenuBarLabelView(widgetManager: widgetManager)
                .modifier(OpenDashboardBridge())
        }
        .menuBarExtraStyle(.window)

        // Module mode: one item per widget, each inserted only when module mode
        // is active and that widget is enabled in Settings. The catalogue is
        // enumerated statically because `@SceneBuilder` cannot `ForEach` a runtime
        // collection into scenes; this order is the initial left-to-right order
        // (macOS lets the user ⌘-drag to rearrange thereafter).
        Group {
            moduleItem("cpu")
            moduleItem("ram")
            moduleItem("gpu")
            moduleItem("network")
            moduleItem("battery")
            moduleItem("ssd")
            moduleItem("thermal")
        }
    }

    private func moduleItem(_ id: String) -> some Scene {
        ModuleMenuBarExtra(appState: appState, widgetManager: widgetManager, widgetId: id)
    }

    /// Get reflects the active mode; set is a no-op so dragging the item out of
    /// the menu bar does not silently switch modes.
    private var compactInsertedBinding: Binding<Bool> {
        Binding(
            get: { widgetManager.presentationMode == .compact },
            set: { _ in /* mode is controlled only by Settings — no-op */ }
        )
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
                .accessibilityLabel("iStatus Monitor: collecting metrics")
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

/// A single widget's icon + value in the menu bar label. Internal so module-mode
/// labels (`ModuleMenuBarLabel`) render identically to compact-mode segments.
struct MenuBarSegmentView: View {
    let segment: MenuBarSegment

    var body: some View {
        HStack(spacing: 3) {
            if segment.showsIcon {
                Image(systemName: segment.sfSymbol)
            }
            Text(segment.text)
        }
        .foregroundStyle(menuBarColor(for: segment.severity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.accessibilityLabel)
    }
}

// MARK: - Popover

/// A lightweight menu-bar popover listing the current metrics. It is *not* a
/// second dashboard — it reuses each widget's own formatting and reads values
/// straight from `AppState`. Only widgets with data are shown.
private struct MenuBarPopoverView: View {
    let appState: AppState
    let widgetManager: WidgetManager

    @Environment(\.openWindow) private var openWindow

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

            Button("Open Dashboard") {
                openWindow(id: iStatus_MonitorApp.dashboardWindowID)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widget.accessibilityLabel(from: appState))
    }
}

// MARK: - Open Dashboard Bridge

/// Listens for `.openDashboardWindow` (posted by the notification delegate when
/// the user taps an alert) and opens the dashboard window via SwiftUI's
/// `openWindow`. Attached to an always-present view so it works even when no
/// window is currently open.
private struct OpenDashboardBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .openDashboardWindow)) { _ in
            openWindow(id: iStatus_MonitorApp.dashboardWindowID)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Severity Color

/// Maps a `WidgetSeverity` to a SwiftUI `Color` for the view layer. (The
/// renderer has its own copy for `AttributedString`; keeping `Color` out of
/// `WidgetSeverity` lets the protocol layer stay free of SwiftUI.) Internal so
/// module-mode views share one mapping.
func menuBarColor(for severity: WidgetSeverity) -> Color {
    switch severity {
    case .normal: .primary
    case .warning: .orange
    case .critical: .red
    }
}
