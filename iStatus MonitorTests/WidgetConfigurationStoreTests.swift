import Foundation
import Testing
@testable import iStatus_Monitor

/// Pure-logic coverage for `WidgetConfigurationStore`: ordering/normalization,
/// enable/disable, reordering, reconciliation, and the UserDefaults persistence
/// round-trip. Each test uses an isolated UUID-suite `UserDefaults` so there is
/// no shared global state (mirrors the AlertEngineTests pattern).
@MainActor
struct WidgetConfigurationStoreTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WidgetConfigStoreTests-\(UUID().uuidString)")!
    }

    private var seed: [WidgetConfiguration] {
        [
            WidgetConfiguration(widgetId: "cpu", isEnabled: true, order: 0),
            WidgetConfiguration(widgetId: "ram", isEnabled: false, order: 1),
            WidgetConfiguration(widgetId: "gpu", isEnabled: false, order: 2)
        ]
    }

    @Test("seeds default configurations in order on first launch")
    func seedsDefaults() {
        let store = WidgetConfigurationStore(defaults: makeDefaults(), defaultConfigurations: seed)
        #expect(store.configurations.map(\.widgetId) == ["cpu", "ram", "gpu"])
        #expect(store.enabledConfigurations().map(\.widgetId) == ["cpu"])
        #expect(store.layout == .default)
        #expect(store.presentationMode == .default)
    }

    @Test("normalize sorts by order and renumbers contiguously")
    func normalizesOutOfOrderSeed() {
        let messy = [
            WidgetConfiguration(widgetId: "b", isEnabled: false, order: 9),
            WidgetConfiguration(widgetId: "a", isEnabled: false, order: 4)
        ]
        let store = WidgetConfigurationStore(defaults: makeDefaults(), defaultConfigurations: messy)
        #expect(store.configurations.map(\.widgetId) == ["a", "b"])
        #expect(store.configurations.map(\.order) == [0, 1])
    }

    @Test("toggleEnabled flips enabled state")
    func toggleEnabled() {
        let store = WidgetConfigurationStore(defaults: makeDefaults(), defaultConfigurations: seed)
        store.toggleEnabled(for: "ram")
        #expect(store.enabledConfigurations().map(\.widgetId) == ["cpu", "ram"])
        store.toggleEnabled(for: "cpu")
        #expect(store.enabledConfigurations().map(\.widgetId) == ["ram"])
    }

    @Test("move reorders and reindexes order to stay contiguous")
    func moveReorders() {
        let store = WidgetConfigurationStore(defaults: makeDefaults(), defaultConfigurations: seed)
        // Move "gpu" (index 2) to the front.
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.configurations.map(\.widgetId) == ["gpu", "cpu", "ram"])
        #expect(store.configurations.map(\.order) == [0, 1, 2])
    }

    @Test("configuration changes persist across store instances")
    func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let store = WidgetConfigurationStore(defaults: defaults, defaultConfigurations: seed)
        store.toggleEnabled(for: "ram")
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3) // cpu to the end
        store.layout = .detailed

        // A fresh store reading the same defaults must observe the saved state.
        let reloaded = WidgetConfigurationStore(defaults: defaults, defaultConfigurations: seed)
        #expect(reloaded.configurations.map(\.widgetId) == ["ram", "gpu", "cpu"])
        #expect(reloaded.enabledConfigurations().map(\.widgetId).contains("ram"))
        #expect(reloaded.layout == .detailed)
    }

    @Test("synchronize drops removed widgets and appends new ones")
    func synchronizeReconciles() {
        let store = WidgetConfigurationStore(defaults: makeDefaults(), defaultConfigurations: seed)
        // "ram"/"gpu" disappear; "thermal" appears.
        store.synchronize(withAvailableIDs: ["cpu", "thermal"])
        #expect(Set(store.configurations.map(\.widgetId)) == ["cpu", "thermal"])
        #expect(store.configurations.map(\.order) == [0, 1])
    }

    @Test("setDisplayStyle updates only the targeted widget")
    func setDisplayStyle() {
        let store = WidgetConfigurationStore(defaults: makeDefaults(), defaultConfigurations: seed)
        store.setDisplayStyle(.iconAndValue, for: "cpu")
        #expect(store.configuration(for: "cpu")?.displayStyle == .iconAndValue)
        #expect(store.configuration(for: "ram")?.displayStyle == .default)
    }

    @Test("restoreDefaults reverts configuration and layout")
    func restoreDefaults() {
        let store = WidgetConfigurationStore(defaults: makeDefaults(), defaultConfigurations: seed)
        store.toggleEnabled(for: "ram")
        store.layout = .separated
        store.restoreDefaults()
        #expect(store.enabledConfigurations().map(\.widgetId) == ["cpu"])
        #expect(store.layout == .default)
    }
}
