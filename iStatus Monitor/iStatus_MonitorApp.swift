import AppKit
import SwiftData
import SwiftUI
import UserNotifications

extension Notification.Name {
    /// Posted by the notification delegate when the user taps an alert (or its
    /// "View Dashboard" action). An always-present SwiftUI view observes this and
    /// calls `openWindow`, since AppKit cannot open a SwiftUI `WindowGroup` window
    /// directly.
    static let openDashboardWindow = Notification.Name("iStatusMonitor.openDashboardWindow")
}

/// Owns process-lifetime concerns that must not depend on any window existing:
/// - keeps the app alive after the dashboard window closes (menu-bar utility),
/// - starts metric/alert monitoring at launch so alerts fire even if the
///   dashboard is never opened (B1),
/// - acts as the `UNUserNotificationCenterDelegate` so alerts present while the
///   app is active and the "View Dashboard" action works (B8).
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the App composition root. Invoked once, after launch, on the main
    /// actor — independent of any window's lifecycle.
    var onFinishLaunching: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        onFinishLaunching?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Present alerts as banners even while the app is active/foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Handle taps on an alert (default action) and on the "View Dashboard"
    /// button: bring the app forward and ask SwiftUI to open the dashboard.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openDashboardWindow, object: nil)
    }
}

@main
struct iStatus_MonitorApp: App {
    /// Scene id for the dashboard window, so menu bar actions can open it via
    /// `openWindow`. Required for an `LSUIElement` app: no window auto-opens at
    /// launch, so the dashboard must be openable on demand.
    static let dashboardWindowID = "dashboard"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var appState: AppState
    @State private var menuBarSettings = MenuBarSettings()

    // New widget-based menu bar stack (replaces MenuBarManager / NSStatusItem).
    @State private var widgetRegistry: WidgetRegistry
    @State private var widgetConfigStore: WidgetConfigurationStore
    @State private var widgetManager: WidgetManager

    @State private var alertsStore: AlertsStore
    @State private var historyViewModel: HistoryViewModel

    private let monitorService: SystemMonitorService
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([MetricRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Fallback to in-memory storage when persistent storage fails
            do {
                let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [inMemoryConfig])
                #if DEBUG
                print("⚠️  SwiftData persistent storage unavailable, using in-memory storage")
                #endif
            } catch {
                fatalError("Failed to initialize SwiftData (persistent and in-memory): \(error)")
            }
        }

        modelContainer = container

        let alertEngine = AlertEngine()
        let historyStore = HistoryStore(modelContainer: container)

        _alertsStore = State(initialValue: AlertsStore(engine: alertEngine))
        _historyViewModel = State(initialValue: HistoryViewModel(historyStore: historyStore))

        monitorService = SystemMonitorService(alertEngine: alertEngine, historyStore: historyStore)

        // Single live-metrics source of truth, shared by the UI and the menu bar.
        let appState = AppState()
        _appState = State(initialValue: appState)

        // Menu bar presentation layer. The registry is the widget catalogue, the
        // store is the only config source, and the manager is the facade the
        // MenuBarExtra scene and the settings panel both read from. No timers —
        // it derives everything from AppState via Observation.
        let registry = WidgetRegistry(widgets: WidgetRegistry.builtInWidgets())
        let configStore = WidgetConfigurationStore(
            defaultConfigurations: Self.defaultWidgetConfigurations()
        )
        let manager = WidgetManager(
            appState: appState,
            registry: registry,
            configurationStore: configStore
        )
        _widgetRegistry = State(initialValue: registry)
        _widgetConfigStore = State(initialValue: configStore)
        _widgetManager = State(initialValue: manager)

        // Start monitoring at process launch, independent of any window. This is
        // the fix for B1: as an `LSUIElement` app no window opens automatically,
        // so a window-bound `.task` would leave alerts dormant until the user
        // manually opened the dashboard. `start()` is idempotent (guards on
        // `loopTask == nil`), so the redundant `.task` below is harmless.
        let service = monitorService
        let launchInterval = Self.storedUpdateInterval()
        appDelegate.onFinishLaunching = {
            Task { await service.start(appState: appState, interval: launchInterval) }
        }
    }

    /// The persisted Settings "Update interval" (seconds), as a `Duration`, used
    /// so the saved cadence applies from launch — not just after the slider is
    /// touched. Defaults to 1s, matching the Settings default, and clamps to the
    /// slider's 0.5–5s range.
    private static func storedUpdateInterval() -> Duration {
        let stored = UserDefaults.standard.object(forKey: "updateInterval") as? Double ?? 1.0
        let clamped = min(max(stored, 0.5), 5.0)
        return .seconds(clamped)
    }

    var body: some Scene {
        WindowGroup(id: Self.dashboardWindowID) {
            MainNavigationShell(appState: appState, alertsStore: alertsStore, historyViewModel: historyViewModel)
                .task {
                    await monitorService.start(appState: appState, interval: Self.storedUpdateInterval())
                }
                .onAppear {
                    // Re-apply the saved Dock-icon policy here, not in
                    // MenuBarSettings.init: a setActivationPolicy call during App
                    // init is overridden when the WindowGroup activates, so it must
                    // run after launch to stick.
                    menuBarSettings.applyActivationPolicy()
                    alertsStore.refresh()
                    historyViewModel.reload()
                }
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 760)

        // Native menu bar presence — replaces the old NSStatusItem system.
        MenuBarExtraScene(appState: appState, widgetManager: widgetManager)

        Settings {
            SettingsView(widgetManager: widgetManager, menuBarSettings: menuBarSettings, monitorService: monitorService)
        }

        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    /// Default menu bar widget set: CPU, RAM, and Network enabled; GPU, Battery,
    /// SSD, and Thermal available but off by default. Used on first launch and
    /// by "Reset to Defaults".
    private static func defaultWidgetConfigurations() -> [WidgetConfiguration] {
        [
            WidgetConfiguration(widgetId: "cpu", isEnabled: true, order: 0, displayStyle: .labelAndValue),
            WidgetConfiguration(widgetId: "ram", isEnabled: true, order: 1, displayStyle: .labelAndValue),
            WidgetConfiguration(widgetId: "network", isEnabled: true, order: 2, displayStyle: .iconAndValue),
            WidgetConfiguration(widgetId: "gpu", isEnabled: false, order: 3, displayStyle: .labelAndValue),
            WidgetConfiguration(widgetId: "battery", isEnabled: false, order: 4, displayStyle: .labelAndValue),
            WidgetConfiguration(widgetId: "ssd", isEnabled: false, order: 5, displayStyle: .labelAndValue),
            WidgetConfiguration(widgetId: "thermal", isEnabled: false, order: 6, displayStyle: .labelAndValue),
        ]
    }
}
