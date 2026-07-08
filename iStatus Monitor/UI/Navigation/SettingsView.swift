import SwiftUI

struct SettingsView: View {
    let widgetManager: WidgetManager
    @Bindable var menuBarSettings: MenuBarSettings
    let monitorService: SystemMonitorService
    
    @AppStorage("defaultTab") private var defaultTab: String = NavigationTab.dashboard.rawValue
    @AppStorage("updateInterval") private var updateInterval: Double = 1.0
    
    @AppStorage("useSystemAccent") private var useSystemAccent: Bool = true
    @AppStorage("accentRed") private var accentRed: Double = 0.15
    @AppStorage("accentGreen") private var accentGreen: Double = 0.50
    @AppStorage("accentBlue") private var accentBlue: Double = 0.95
    
    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }
            
            appearanceSettings
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            
            MenuBarSettingsPanel(widgetManager: widgetManager, menuBarSettings: menuBarSettings)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            
            aboutSettings
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520)
        .tint(useSystemAccent ? nil : Color(red: accentRed, green: accentGreen, blue: accentBlue))
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
            Task { await monitorService.updateInterval(.seconds(newValue)) }
        }
    }
    
    private var appearanceSettings: some View {
        Form {
            Section {
                Toggle("Follow system accent color", isOn: $useSystemAccent)
                
                ColorPicker("Accent color", selection: accentBinding, supportsOpacity: false)
                    .disabled(useSystemAccent)
            } header: {
                Text("Appearance")
            } footer: {
                if useSystemAccent {
                    Text("Using the accent color set in System Settings › Appearance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
    
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
    
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("iStatus Monitor")
                .font(.title2.weight(.semibold))
            
            LabeledContent(
                "Version",
                value: "\(appVersion) (\(buildNumber))"
            )
            
            Link(
                "GitHub",
                destination: URL(string: "https://github.com/PankajKrana/iStatus-Monitor")!
            )
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Acknowledgements")
                    .font(.headline)
                
                Text("Built with SwiftUI, Charts, SwiftData, and system frameworks for macOS telemetry.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
