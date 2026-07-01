import SwiftUI

struct SettingsView: View {
    let widgetManager: WidgetManager
    @Bindable var menuBarSettings: MenuBarSettings
    let monitorService: SystemMonitorService

    @State private var selectedSection: SettingsSection = .general

    @AppStorage("defaultTab") private var defaultTab: String = NavigationTab.dashboard.rawValue
    @AppStorage("updateInterval") private var updateInterval: Double = 1.0

    @AppStorage("accentRed") private var accentRed: Double = 0.15
    @AppStorage("accentGreen") private var accentGreen: Double = 0.50
    @AppStorage("accentBlue") private var accentBlue: Double = 0.95

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case appearance
        case menuBar
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .menuBar: "Menu Bar"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintpalette"
            case .menuBar: "menubar.rectangle"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .listStyle(.sidebar)
        } detail: {
            settingsContent
                .navigationTitle(selectedSection.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 520)
        .tint(Color(red: accentRed, green: accentGreen, blue: accentBlue))
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedSection {
        case .general: generalSettings
        case .appearance: appearanceSettings
        case .menuBar: MenuBarSettingsPanel(widgetManager: widgetManager, menuBarSettings: menuBarSettings)
        case .about: aboutSettings
        }
    }

    private var generalSettings: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $menuBarSettings.launchAtLogin)

                if let error = menuBarSettings.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker("Default tab", selection: $defaultTab) {
                    ForEach(NavigationTab.allCases) { tab in
                        Text(tab.title).tag(tab.rawValue)
                    }
                }

                LabeledContent("Update interval") {
                    HStack {
                        Slider(value: $updateInterval, in: 0.5 ... 5.0, step: 0.5)
                        Text("\(String(format: "%.1fs", updateInterval))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .onChange(of: updateInterval) { _, newValue in
            // Apply the new cadence immediately by restarting the sampling loop.
            Task { await monitorService.updateInterval(.seconds(newValue)) }
        }
    }

    private var appearanceSettings: some View {
        Form {
            Section("Appearance") {
                ColorPicker("Accent color", selection: accentBinding, supportsOpacity: false)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("iStatus Monitor")
                .font(.title2.weight(.semibold))

            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")

            Link("GitHub", destination: URL(string: "https://github.com/PankajKrana/iStatus-Monitor")!)

            Text("Acknowledgements")
                .font(.headline)
            Text("Built with SwiftUI, Charts, SwiftData, and system frameworks for macOS telemetry.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }

    private var accentBinding: Binding<Color> {
        Binding {
            Color(red: accentRed, green: accentGreen, blue: accentBlue)
        } set: { color in
            #if os(macOS)
            let ns = NSColor(color)
            guard let rgb = ns.usingColorSpace(.deviceRGB) else { return }
            accentRed = rgb.redComponent
            accentGreen = rgb.greenComponent
            accentBlue = rgb.blueComponent
            #endif
        }
    }
}

#Preview {
    SettingsView(
        widgetManager: WidgetManager(
            appState: AppState(),
            registry: WidgetRegistry(widgets: WidgetRegistry.builtInWidgets()),
            configurationStore: WidgetConfigurationStore()
        ),
        menuBarSettings: MenuBarSettings(),
        monitorService: SystemMonitorService()
    )
}
