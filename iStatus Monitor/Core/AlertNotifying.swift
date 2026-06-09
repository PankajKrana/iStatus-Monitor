import Foundation
import UserNotifications

/// A single user-facing notification payload, independent of `UserNotifications`
/// construction details so it can be produced and tested without a live
/// `UNUserNotificationCenter`.
struct AlertNotification: Sendable {
    var title: String
    var body: String
    var categoryIdentifier: String
    var threadIdentifier: String?
    var interruptionLevel: UNNotificationInterruptionLevel = .active
}

/// Abstraction over the system notification center. Injecting this lets the
/// alert engine be unit-tested deterministically (delivery always succeeds in a
/// stub) while production code talks to `UNUserNotificationCenter`.
protocol AlertNotifying: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async
    /// Delivers the notification. Returns `false` when notifications are not
    /// authorized or the system rejects the request, so callers can avoid
    /// recording undelivered alerts.
    @discardableResult
    func deliver(_ notification: AlertNotification) async -> Bool
    func configureCategories() async
}

/// Production `AlertNotifying` backed by `UNUserNotificationCenter`. Modeled as an
/// actor so it is `Sendable` without unchecked annotations.
actor SystemNotifier: AlertNotifying {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    @discardableResult
    func deliver(_ notification: AlertNotification) async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return false }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = notification.categoryIdentifier
        content.interruptionLevel = notification.interruptionLevel
        if let threadIdentifier = notification.threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func configureCategories() async {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_DASHBOARD",
            title: "View Dashboard",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "ALERT_VIEW_DASHBOARD",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }
}
