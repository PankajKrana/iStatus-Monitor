import Foundation
import UserNotifications

actor BatteryAlertService {
    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private let lowChargeCooldownKey = "battery.alert.lowCharge.last"
    private let tempCooldownKey = "battery.alert.temp.last"
    private let health80Key = "battery.alert.health80.sent"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func evaluate(_ snapshot: BatterySnapshot?) async {
        guard let snapshot else { return }

        if snapshot.chargePercent < 20, snapshot.chargeState == .discharging {
            await notifyWithCooldown(
                key: lowChargeCooldownKey,
                title: "Battery Low",
                body: String(format: "Battery is at %.0f%%. Connect power soon.", snapshot.chargePercent),
                cooldown: 30 * 60
            )
        }

        if snapshot.temperatureCelsius > 45 {
            await notifyWithCooldown(
                key: tempCooldownKey,
                title: "Battery Temperature High",
                body: String(format: "Battery temperature is %.1f°C.", snapshot.temperatureCelsius),
                cooldown: 15 * 60
            )
        }

        if snapshot.healthPercent < 80, defaults.bool(forKey: health80Key) == false {
            defaults.set(true, forKey: health80Key)
            await post(
                title: "Battery Health Reduced",
                body: String(format: "Battery health is now %.1f%%.", snapshot.healthPercent)
            )
        }
    }

    private func notifyWithCooldown(key: String, title: String, body: String, cooldown: TimeInterval) async {
        let now = Date()
        let last = defaults.object(forKey: key) as? Date
        if let last, now.timeIntervalSince(last) < cooldown {
            return
        }
        defaults.set(now, forKey: key)
        await post(title: title, body: body)
    }

    private func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
