import SwiftData
import SwiftUI

@main
struct iStatus_MonitorApp: App {
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
        let historyStore = HistoryStore(container: container)

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
    }

    var body: some Scene {
        WindowGroup {
            MainNavigationShell(appState: appState, alertsStore: alertsStore, historyViewModel: historyViewModel)
                .task {
                    await monitorService.start(appState: appState)
                }
                .onAppear {
                    alertsStore.refresh()
                    historyViewModel.reload()
                }
                .onDisappear {
                    Task {
                        await monitorService.stop()
                    }
                }
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 760)

        // Native menu bar presence — replaces the old NSStatusItem system.
        MenuBarExtraScene(appState: appState, widgetManager: widgetManager)

        Settings {
            SettingsView(widgetManager: widgetManager)
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
