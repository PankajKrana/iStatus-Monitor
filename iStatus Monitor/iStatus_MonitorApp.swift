import SwiftUI

@main
struct iStatus_MonitorApp: App {
    @State private var appState = AppState()
    private let monitorService = SystemMonitorService()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .task {
                    await monitorService.start(appState: appState)
                }
                .onDisappear {
                    Task {
                        await monitorService.stop()
                    }
                }
        }

        MenuBarExtra("iStatus", systemImage: "waveform.path.ecg") {
            MenuBarView(
                cpuText: String(format: "CPU %.0f%%", appState.cpu.usagePercent),
                ramText: String(format: "RAM %.0f%%", appState.ram.usedPercent)
            )
        }
    }
}
