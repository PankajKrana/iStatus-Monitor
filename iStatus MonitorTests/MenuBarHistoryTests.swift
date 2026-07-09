import Foundation
import Testing
@testable import iStatus_Monitor

/// Pure-logic coverage for the sparkline history buffers. No hardware, no timer —
/// just the ring-buffer math that backs the menu bar graphs.
struct MenuBarHistoryTests {

    // MARK: Ring Buffer

    @Test("ring buffer keeps most-recent up to capacity, in order")
    func ringBufferCapacityAndOrder() {
        var buffer = RingBuffer<Double>(capacity: 3)
        (1...5).forEach { buffer.append(Double($0)) }

        #expect(buffer.count == 3)
        #expect(buffer.values == [3, 4, 5])          // oldest (1, 2) dropped
    }

    @Test("ring buffer does not grow below capacity")
    func ringBufferBelowCapacity() {
        var buffer = RingBuffer<Int>(capacity: 5)
        buffer.append(contentsOf: [10, 20])
        #expect(buffer.values == [10, 20])
        #expect(buffer.count == 2)
    }

    // MARK: Menu Bar History

    @Test("records samples per widget, ignores nil and unknown ids")
    func recordsPerWidget() {
        var history = MenuBarHistory()

        history.record(42, for: "cpu")
        history.record(43, for: "cpu")
        history.record(nil, for: "battery")          // desktop / no snapshot
        history.record(50, for: "unknown")           // not tracked

        #expect(history.values(for: "cpu") == [42, 43])
        #expect(history.values(for: "battery").isEmpty)
        #expect(history.values(for: "unknown").isEmpty)
    }

    @Test("rolls over at capacity, preserving widget independence")
    func rollsOverAndIsolatesWidgets() {
        var history = MenuBarHistory()

        for i in 0..<MenuBarHistory.capacity + 10 {
            history.record(Double(i), for: "ram")
            history.record(1, for: "cpu")            // stays well under capacity
        }

        let ram = history.values(for: "ram")
        #expect(ram.count == MenuBarHistory.capacity)
        #expect(ram.first == Double(10))             // oldest 0..<10 dropped
        #expect(ram.last == Double(MenuBarHistory.capacity + 9))
        // "cpu" (70 records) also rolls over at capacity — both stay at 60.
        #expect(history.values(for: "cpu").count == MenuBarHistory.capacity)
    }
}
