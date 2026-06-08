import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case miniChart
    case text

    var id: String { rawValue }
}

@MainActor
@Observable
final class MenuBarSettings {
    var displayMode: MenuBarDisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    var showCPU: Bool {
        didSet { defaults.set(showCPU, forKey: Keys.showCPU) }
    }

    var showRAM: Bool {
        didSet { defaults.set(showRAM, forKey: Keys.showRAM) }
    }

    var showNetwork: Bool {
        didSet { defaults.set(showNetwork, forKey: Keys.showNetwork) }
    }

    var showBattery: Bool {
        didSet { defaults.set(showBattery, forKey: Keys.showBattery) }
    }

    var showTemperature: Bool {
        didSet { defaults.set(showTemperature, forKey: Keys.showTemperature) }
    }

    var showGPU: Bool {
        didSet { defaults.set(showGPU, forKey: Keys.showGPU) }
    }

    var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
            applyActivationPolicy()
        }
    }

    /// Inverse of `showDockIcon`, exposed for a "Hide Dock Icon" control. Backed
    /// entirely by `showDockIcon` — same UserDefaults key and the same
    /// `applyActivationPolicy()` side effect — so there is no separate preference.
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

    /// Set when an `SMAppService` registration change fails, so the UI can show
    /// the user why the toggle did not take effect. Cleared on the next success.
    private(set) var launchAtLoginError: String?

    /// Guards against the revert assignment in `applyLaunchAtLogin` re-entering the
    /// `didSet` side effect and looping.
    private var isRevertingLaunchAtLogin = false

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iStatus-Monitor",
                                category: "LaunchAtLogin")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        displayMode = MenuBarDisplayMode(rawValue: defaults.string(forKey: Keys.displayMode) ?? "") ?? .miniChart
        showCPU = defaults.object(forKey: Keys.showCPU) as? Bool ?? true
        showRAM = defaults.object(forKey: Keys.showRAM) as? Bool ?? true
        showNetwork = defaults.object(forKey: Keys.showNetwork) as? Bool ?? true
        showBattery = defaults.object(forKey: Keys.showBattery) as? Bool ?? true
        showTemperature = defaults.object(forKey: Keys.showTemperature) as? Bool ?? true
        showGPU = defaults.object(forKey: Keys.showGPU) as? Bool ?? true
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
            // Persist only the value the system actually accepted.
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            launchAtLoginError = nil
            logger.info("Launch at login \(self.launchAtLogin ? "enabled" : "disabled", privacy: .public)")
        } catch {
            // Registration was rejected (e.g. unsigned build, daemon refusal).
            // Surface it and roll the toggle back so the UI never lies about state.
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
        static let displayMode = "menuBar.displayMode"
        static let showCPU = "menuBar.showCPU"
        static let showRAM = "menuBar.showRAM"
        static let showNetwork = "menuBar.showNetwork"
        static let showBattery = "menuBar.showBattery"
        static let showTemperature = "menuBar.showTemperature"
        static let showGPU = "menuBar.showGPU"
        static let showDockIcon = "menuBar.showDockIcon"
        static let launchAtLogin = "menuBar.launchAtLogin"
    }
}
