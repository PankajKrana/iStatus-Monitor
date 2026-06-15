import Foundation
import Testing
@testable import iStatus_Monitor

/// Pure-logic coverage for the menu-bar widgets and the renderer. Every method is
/// a deterministic read over a hand-built `AppState`, so no hardware is touched.
/// This also guards the accessibility wiring: segments must carry the widget's
/// VoiceOver phrase, not just the abbreviated visible text.
@MainActor
struct MenuBarWidgetTests {

    // MARK: Helpers

    private func makeBattery(charge: Double) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            currentCapacitymAh: 5000,
            designCapacitymAh: 6000,
            healthPercent: 90,
            cycleCount: 100,
            chargeState: .discharging,
            chargePercent: charge,
            timeToEmptyMinutes: 120,
            timeToFullMinutes: nil,
            voltageMillivolts: 12000,
            amperageMilliamps: -1000,
            watts: 12,
            temperatureCelsius: 30,
            temperatureFahrenheit: 86,
            serialNumber: "TEST",
            chargeHistory24h: [],
            healthHistory: []
        )
    }

    private func makeThermal(maxCelsius: Double, state: ProcessInfo.ThermalState) -> ThermalSnapshot {
        ThermalSnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            fans: [],
            sensors: [
                ThermalSensor(key: "TC0P", name: "CPU", celsius: maxCelsius - 5, fahrenheit: 0, zone: .cpu),
                ThermalSensor(key: "TG0P", name: "GPU", celsius: maxCelsius, fahrenheit: 0, zone: .gpu)
            ],
            thermalState: state
        )
    }

    // MARK: CPU

    @Test("CPU widget formats value, label, and severity")
    func cpuWidget() {
        let appState = AppState()
        let widget = CPUWidget()

        appState.cpu = CPUMetrics(usagePercent: 42, coreCount: 8, temperatureCelsius: nil)
        #expect(widget.formattedValue(from: appState) == "42%")
        #expect(widget.accessibilityLabel(from: appState) == "CPU: 42 percent")
        #expect(widget.severity(from: appState) == .normal)

        appState.cpu = CPUMetrics(usagePercent: 75, coreCount: 8, temperatureCelsius: nil)
        #expect(widget.severity(from: appState) == .warning)

        appState.cpu = CPUMetrics(usagePercent: 95, coreCount: 8, temperatureCelsius: nil)
        #expect(widget.severity(from: appState) == .critical)
    }

    // MARK: RAM

    @Test("RAM widget is unavailable until totalBytes is known")
    func ramWidgetGating() {
        let appState = AppState()
        let widget = RAMWidget()

        // No total yet → no data.
        #expect(widget.currentValue(from: appState) == nil)
        #expect(widget.formattedValue(from: appState) == "")

        appState.ram = MemoryMetrics(usedBytes: 8 * 1024 * 1024 * 1024, totalBytes: 16 * 1024 * 1024 * 1024)
        #expect(widget.formattedValue(from: appState) == "50%")
        #expect(widget.accessibilityLabel(from: appState) == "RAM: 50 percent")
    }

    // MARK: Battery (inverted severity)

    @Test("Battery widget inverts severity — low charge is worse")
    func batteryWidgetInvertedSeverity() {
        let appState = AppState()
        let widget = BatteryWidget()

        appState.batterySnapshot = makeBattery(charge: 80)
        #expect(widget.formattedValue(from: appState) == "80%")
        #expect(widget.severity(from: appState) == .normal)

        appState.batterySnapshot = makeBattery(charge: 15)
        #expect(widget.severity(from: appState) == .warning)

        appState.batterySnapshot = makeBattery(charge: 5)
        #expect(widget.severity(from: appState) == .critical)
    }

    @Test("Battery widget has no data on a desktop")
    func batteryWidgetNoBattery() {
        let appState = AppState()
        let widget = BatteryWidget()
        #expect(widget.currentValue(from: appState) == nil)
        #expect(!widget.hasData(in: appState))
    }

    // MARK: Thermal (state-driven severity)

    @Test("Thermal widget reports hottest sensor and state-driven severity")
    func thermalWidget() {
        let appState = AppState()
        let widget = ThermalWidget()

        appState.thermalSnapshot = makeThermal(maxCelsius: 72, state: .nominal)
        #expect(widget.formattedValue(from: appState) == "72°C")
        #expect(widget.severity(from: appState) == .normal)

        appState.thermalSnapshot = makeThermal(maxCelsius: 88, state: .fair)
        #expect(widget.severity(from: appState) == .warning)

        appState.thermalSnapshot = makeThermal(maxCelsius: 99, state: .serious)
        #expect(widget.severity(from: appState) == .critical)
    }

    // MARK: Renderer — accessibility wiring

    @Test("renderer threads the widget's accessibility label into the segment")
    func rendererPopulatesAccessibilityLabel() {
        let appState = AppState()
        appState.cpu = CPUMetrics(usagePercent: 42, coreCount: 8, temperatureCelsius: nil)

        let config = WidgetConfiguration(widgetId: "cpu", isEnabled: true, order: 0, displayStyle: .valueOnly)
        let renderer = MenuBarRenderer(layout: .compact)
        let segments = renderer.segments(for: [(CPUWidget(), config)], appState: appState)

        #expect(segments.first?.text == "42%")                                   // visible text is terse
        #expect(segments.first?.accessibilityLabel == "CPU: 42 percent")          // VoiceOver gets the full phrase
    }

    @Test("renderer respects display style for visible text")
    func rendererDisplayStyle() {
        let appState = AppState()
        appState.cpu = CPUMetrics(usagePercent: 42, coreCount: 8, temperatureCelsius: nil)

        let config = WidgetConfiguration(widgetId: "cpu", isEnabled: true, order: 0, displayStyle: .labelAndValue)
        let renderer = MenuBarRenderer(layout: .compact)
        let segments = renderer.segments(for: [(CPUWidget(), config)], appState: appState)

        #expect(segments.first?.text == "CPU 42%")
    }
}
