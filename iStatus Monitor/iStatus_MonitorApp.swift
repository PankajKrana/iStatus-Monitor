import SwiftUI

@main
struct iStatus_MonitorApp: App {
    @State private var appState = AppState()
    @State private var menuBarSettings = MenuBarSettings()
    @State private var menuBarManager: MenuBarManager?

    private let alertEngine = AlertEngine()
    @State private var alertsStore: AlertsStore
    private let monitorService: SystemMonitorService

    init() {
        let engine = AlertEngine()
        _alertsStore = State(initialValue: AlertsStore(engine: engine))
        monitorService = SystemMonitorService(alertEngine: engine)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState, alertsStore: alertsStore)
                .task {
                    await monitorService.start(appState: appState)
                }
                .onAppear {
                    alertsStore.refresh()
                    if menuBarManager == nil {
                        let manager = MenuBarManager(appState: appState, settings: menuBarSettings)
                        manager.start()
                        menuBarManager = manager
                    }
                }
                .onDisappear {
                    Task {
                        await monitorService.stop()
                    }
                    menuBarManager?.stop()
                }
        }

        Settings {
            SettingsView(settings: menuBarSettings)
        }
    }
}
