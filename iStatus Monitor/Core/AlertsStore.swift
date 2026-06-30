import AppKit
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AlertsStore {
    private let engine: AlertEngine

    var rules: [AlertRule] = []
    var history: [AlertHistoryEntry] = []
    var badgeCountLastHour: Int = 0
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Active "snooze all" expiry, or nil when alerts aren't globally snoozed.
    var globalSnoozeUntil: Date?

    /// One-shot task that refreshes when the global snooze elapses. The engine
    /// auto-expires silently (no change event), so without this the banner/icon
    /// stay stale until the next alert or edit. Cancelled + rescheduled on every
    /// refresh; on fire it re-reads the now-expired (nil) snooze.
    @ObservationIgnored private var globalSnoozeExpiry: Task<Void, Never>?

    /// True when notifications can actually be delivered. Drives the "enable
    /// notifications" call-to-action in the UI.
    var notificationsEnabled: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    /// True only once we know the user explicitly turned notifications off, so the
    /// UI doesn't flash a warning during the initial `notDetermined` window.
    var notificationsDenied: Bool {
        authorizationStatus == .denied
    }

    init(engine: AlertEngine) {
        self.engine = engine
        observeEngineChanges()
    }

    /// Subscribe to engine change events so history/badge update live when an
    /// alert fires in the background — not just on `onAppear`/save (B7).
    private func observeEngineChanges() {
        Task { [weak self] in
            guard let self else { return }
            let stream = await engine.changes()
            for await _ in stream {
                self.refresh()
            }
        }
    }

    func refresh() {
        Task {
            rules = await engine.getRules()
            history = await engine.getHistory()
            badgeCountLastHour = await engine.recentAlertCount(last: 3600)
            authorizationStatus = await engine.authorizationStatus()
            globalSnoozeUntil = await engine.currentGlobalSnooze()
            scheduleGlobalSnoozeExpiry()
        }
    }

    /// Schedule a single refresh at the global-snooze expiry so the banner/icon
    /// clear themselves with no polling. No-op when nothing is snoozed.
    private func scheduleGlobalSnoozeExpiry() {
        globalSnoozeExpiry?.cancel()
        guard let until = globalSnoozeUntil else { return }
        globalSnoozeExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            if !Task.isCancelled { self?.refresh() }
        }
    }

    func saveRule(_ rule: AlertRule) {
        Task {
            await engine.upsertRule(rule)
            refresh()
        }
    }

    func deleteRule(id: UUID) {
        Task {
            await engine.deleteRule(id: id)
            refresh()
        }
    }

    func clearHistory() {
        Task {
            await engine.clearHistory()
            refresh()
        }
    }

    func snoozeRule(id: UUID, until: Date) {
        Task {
            await engine.snoozeRule(id: id, until: until)
            refresh()
        }
    }

    func clearSnooze(id: UUID) {
        Task {
            await engine.clearSnooze(id: id)
            refresh()
        }
    }

    func snoozeAll(until: Date) {
        Task {
            await engine.snoozeAll(until: until)
            refresh()
        }
    }

    func clearGlobalSnooze() {
        Task {
            await engine.clearGlobalSnooze()
            refresh()
        }
    }

    func testRule(id: UUID) {
        Task {
            await engine.fireTestAlert(ruleID: id)
        }
    }

    /// Re-request authorization (used by the "Enable Notifications" CTA). When the
    /// user previously denied, this opens System Settings instead, since macOS
    /// won't show the prompt again.
    func requestNotificationAccess() {
        Task {
            if authorizationStatus == .denied {
                openNotificationSettings()
            } else {
                await engine.requestAuthorizationIfNeeded()
                refresh()
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
