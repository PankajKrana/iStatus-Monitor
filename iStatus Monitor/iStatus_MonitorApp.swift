import SwiftData
import SwiftUI

@main
struct iStatus_MonitorApp: App {
    @State private var appState = AppState()
    @State private var menuBarSettings = MenuBarSettings()
    @State private var menuBarManager: MenuBarManager?

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
            // Fallback in-memory container if persistent container cannot be opened.
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }

        modelContainer = container

        let alertEngine = AlertEngine()
        let historyStore = HistoryStore(container: container)

        _alertsStore = State(initialValue: AlertsStore(engine: alertEngine))
        _historyViewModel = State(initialValue: HistoryViewModel(historyStore: historyStore))

        monitorService = SystemMonitorService(alertEngine: alertEngine, historyStore: historyStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState, alertsStore: alertsStore, historyViewModel: historyViewModel)
                .task {
                    await monitorService.start(appState: appState)
                }
                .onAppear {
                    alertsStore.refresh()
                    historyViewModel.reload()

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
        .modelContainer(modelContainer)

        Settings {
            SettingsView(settings: menuBarSettings)
        }
    }
}
