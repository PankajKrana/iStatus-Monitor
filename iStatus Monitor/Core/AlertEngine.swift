import Foundation
import UserNotifications

actor AlertEngine {
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func evaluate(_ snapshot: SystemSnapshot) async {
        if snapshot.cpu.usagePercent >= 90 {
            await post(title: "High CPU Usage", body: String(format: "CPU at %.0f%%", snapshot.cpu.usagePercent))
        }

        if snapshot.ram.usedPercent >= 90 {
            await post(title: "High Memory Pressure", body: String(format: "RAM at %.0f%%", snapshot.ram.usedPercent))
        }
    }

    private func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
