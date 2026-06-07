import SwiftData
import SwiftUI

struct MainNavigationShell: View {
    @Bindable var appState: AppState
    @Bindable var alertsStore: AlertsStore
    @Bindable var historyViewModel: HistoryViewModel

    @AppStorage("defaultTab") private var defaultTab: String = NavigationTab.dashboard.rawValue
    @SceneStorage("last-selected-tab") private var lastSelectedTab: String = NavigationTab.dashboard.rawValue
    @SceneStorage("main-window-frame") private var windowFrameStorage: String = ""

    @State private var selectedTab: NavigationTab = .dashboard
    @State private var searchText: String = ""
    @State private var showOnboarding: Bool = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(NavigationTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                        .keyboardShortcut(tab.keyboardShortcut)
                }
            }
            .navigationSplitViewColumnWidth(min: AppTheme.sidebarWidth, ideal: AppTheme.sidebarWidth)
            .listStyle(.sidebar)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selectedTab.title)
                .navigationSubtitle(String(format: "CPU %.1f%%", appState.cpu.usagePercent))
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if selectedTab == .cpu {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filter processes", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: 240)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: exportMetricsData()) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share current metrics")

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Open Settings")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowFrameBridge(frameStorage: $windowFrameStorage))
        .onAppear {
            restoreSelection()
            checkFirstLaunch()
        }
        .onChange(of: selectedTab) { _, newTab in
            lastSelectedTab = newTab.rawValue
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet()
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView(appState: appState, alertsStore: alertsStore) { tab in
                selectedTab = tab
            }
        case .cpu:
            if let snapshot = appState.cpuSnapshot {
                CPUView(snapshot: snapshot, temperatureCelsius: appState.cpu.temperatureCelsius, searchText: searchText)
                    .padding(16)
            } else {
                EmptySectionView(symbol: "cpu", title: "No CPU Data", message: "CPU metrics will appear when monitoring starts.")
            }
        case .memory:
            if let snapshot = appState.memorySnapshot {
                MemoryView(snapshot: snapshot)
                    .padding(16)
            } else {
                EmptySectionView(symbol: "memorychip", title: "No Memory Data", message: "Memory metrics are currently unavailable.")
            }
        case .disk:
            if let snapshot = appState.diskSnapshot, !snapshot.volumes.isEmpty {
                DiskView(snapshot: snapshot)
                    .padding(16)
            } else {
                EmptySectionView(symbol: "internaldrive.fill", title: "No Disk Data", message: "Disk metrics will appear when monitoring starts.")
            }
        case .network:
            if let snapshot = appState.networkSnapshot {
                NetworkView(snapshot: snapshot)
                    .padding(16)
            } else {
                EmptySectionView(symbol: "network", title: "No Network Data", message: "Network metrics are currently unavailable.")
            }
        case .gpu:
            if let snapshot = appState.gpuSnapshot {
                GPUView(snapshot: snapshot)
                    .padding(16)
            } else {
                EmptySectionView(symbol: "display", title: "No GPU Data", message: "GPU metrics are currently unavailable.")
            }
        case .thermal:
            if let snapshot = appState.thermalSnapshot {
                ThermalView(snapshot: snapshot)
                    .padding(16)
            } else {
                EmptySectionView(symbol: "thermometer.sun.fill", title: "No Thermal Data", message: "Thermal sensors are currently unavailable.")
            }
        case .battery:
            if let snapshot = appState.batterySnapshot {
                BatteryView(snapshot: snapshot)
                    .padding(16)
            } else {
                EmptySectionView(symbol: "battery.0", title: "No Battery Data", message: "Battery data is unavailable on this Mac.")
            }
        case .alerts:
            AlertsView(alertsStore: alertsStore)
        case .history:
            HistoryView(viewModel: historyViewModel)
        }
    }

    private func exportMetricsData() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "iStatus_Metrics_\(formatter.string(from: Date())).txt"

        let content = """
        iStatus Monitor Metrics Export
        \(Date().formatted(date: .abbreviated, time: .standard))

        CPU Usage: \(String(format: "%.1f%%", appState.cpu.usagePercent))
        Memory Usage: \(String(format: "%.1f%%", appState.ram.usedPercent))
        Network Down: \(ByteCountFormatter.string(fromByteCount: Int64(appState.network.bytesInPerSecond), countStyle: .binary))/s
        Network Up: \(ByteCountFormatter.string(fromByteCount: Int64(appState.network.bytesOutPerSecond), countStyle: .binary))/s
        """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    private func restoreSelection() {
        if let tab = NavigationTab(rawValue: lastSelectedTab) {
            selectedTab = tab
            return
        }
        selectedTab = NavigationTab(rawValue: defaultTab) ?? .dashboard
    }

    private func checkFirstLaunch() {
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompleted {
            showOnboarding = true
        }
    }
}

private struct EmptySectionView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct WindowFrameBridge: NSViewRepresentable {
    @Binding var frameStorage: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window, frameStorage: $frameStorage)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window, frameStorage: $frameStorage)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        func attach(to window: NSWindow?, frameStorage: Binding<String>) {
            guard let window, self.window !== window else { return }
            removeObservers()
            self.window = window

            let saved = NSRectFromString(frameStorage.wrappedValue)
            if saved != .zero {
                window.setFrame(saved, display: true)
            }

            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak window] _ in
                guard let frame = window?.frame else { return }
                frameStorage.wrappedValue = NSStringFromRect(frame)
            })
            observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak window] _ in
                guard let frame = window?.frame else { return }
                frameStorage.wrappedValue = NSStringFromRect(frame)
            })
        }

        deinit {
            removeObservers()
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
            observers.removeAll()
        }
    }
}
