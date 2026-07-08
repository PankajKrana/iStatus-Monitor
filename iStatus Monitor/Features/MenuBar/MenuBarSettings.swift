import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement

@MainActor
@Observable
final class MenuBarSettings {
    var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
            applyActivationPolicy()
        }
    }

    /// Inverse of `showDockIcon`, exposed for a "Hide Dock Icon" control.
    var hideDockIcon: Bool {
        get { !showDockIcon }
        set { showDockIcon = !newValue }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !isRevertingLaunchAtLogin else { return }
            applyLaunchAtLogin()
        }
    }

    /// Error message when toggling launch at login fails.
    private(set) var launchAtLoginError: String?

    /// Prevents `didSet` re-entry during revert in `applyLaunchAtLogin`.
    private var isRevertingLaunchAtLogin = false

    private let logger = Logger.menuBar

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? false

        if defaults.object(forKey: Keys.launchAtLogin) == nil {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }

        applyActivationPolicy()
    }

    func applyActivationPolicy() {
        NSApplication.shared.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            launchAtLoginError = nil
            logger.info("Launch at login \(self.launchAtLogin ? "enabled" : "disabled", privacy: .public)")
        } catch {
            // Surface the failure and revert the toggle to reflect actual state.
            let intended = launchAtLogin
            logger.error("Launch at login \(intended ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            launchAtLoginError = error.localizedDescription
            isRevertingLaunchAtLogin = true
            launchAtLogin = !intended
            isRevertingLaunchAtLogin = false
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    private enum Keys {
        static let showDockIcon = "menuBar.showDockIcon"
        static let launchAtLogin = "menuBar.launchAtLogin"
    }
}
