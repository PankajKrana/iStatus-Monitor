import OSLog

/// Centralized OSLog categories. One subsystem (the bundle id), one category per
/// architectural area, so logs are easy to filter in Console.app:
///
///     log stream --predicate 'subsystem == "<bundle id>"'
///     log show   --predicate 'category == "Monitoring"'
///
/// Extensions only — no wrapper class. `Logger` is already lightweight, lazy, and
/// thread-safe. Sensitive values (IPs, user paths) must be interpolated with
/// `privacy: .private`; system error descriptions stay `.public`.
extension Logger {
    /// Bundle id under XCTest is nil, so fall back to a stable string.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "iStatus-Monitor"

    /// App lifecycle, composition root, model container.
    static let app = Logger(subsystem: subsystem, category: "App")

    /// The single sampling loop: start/stop, interval changes, pause/resume.
    static let monitoring = Logger(subsystem: subsystem, category: "Monitoring")

    /// Alert engine, battery alerts, notification authorization and delivery.
    static let alerts = Logger(subsystem: subsystem, category: "Alerts")

    /// Network insights (e.g. public IP lookup).
    static let network = Logger(subsystem: subsystem, category: "Network")

    /// On-disk and SwiftData persistence: metrics log, history store, exports.
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")

    /// Menu bar integration and launch-at-login.
    static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")
}
