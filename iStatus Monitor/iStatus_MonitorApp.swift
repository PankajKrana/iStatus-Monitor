import SwiftUI

@main
struct iStatus_MonitorApp: App {
    @State private var appState = AppState()
    @State private var menuBarSettings = MenuBarSettings()
    @State private var menuBarManager: MenuBarManager?

    private let monitorService = SystemMonitorService()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .task {
                    await monitorService.start(appState: appState)
                }
                .onAppear {
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
