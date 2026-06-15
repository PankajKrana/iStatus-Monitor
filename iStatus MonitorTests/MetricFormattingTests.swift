import Foundation
import Testing
@testable import iStatus_Monitor

/// Pure-logic coverage for the byte/speed formatting helpers used across the UI.
/// These are deterministic and hardware-independent, so they assert on stable
/// substrings rather than exact locale-formatted output.
struct MetricFormattingTests {

    @Test("toMemoryString uses memory (1024) units")
    func memoryStringUnits() {
        #expect((1024).toMemoryString().contains("KB"))
        #expect((5 * 1024 * 1024).toMemoryString().contains("MB"))
        #expect((3 * 1024 * 1024 * 1024).toMemoryString().contains("GB"))
    }

    @Test("toMemoryString scales magnitude correctly")
    func memoryStringMagnitude() {
        // 2 GB should render in GB, not MB/KB.
        let twoGB = (2 * 1024 * 1024 * 1024).toMemoryString()
        #expect(twoGB.contains("GB"))
        #expect(!twoGB.contains("MB"))
    }

    @Test("toNetworkSpeedString always carries a per-second suffix")
    func networkSpeedSuffix() {
        #expect((1).toNetworkSpeedString().hasSuffix("/s"))
        #expect((1_500_000).toNetworkSpeedString().hasSuffix("/s"))
    }

    @Test("toNetworkSpeedString scales into larger units")
    func networkSpeedMagnitude() {
        let fast = (10 * 1024 * 1024).toNetworkSpeedString()
        #expect(fast.contains("MB"))
        #expect(fast.hasSuffix("/s"))
    }

    // MARK: MetricFormat (shared menu-bar/popover formatter)

    @Test("MetricFormat.percent renders a whole-percent string")
    func metricFormatPercent() {
        #expect(MetricFormat.percent(0) == "0%")
        #expect(MetricFormat.percent(42) == "42%")
        #expect(MetricFormat.percent(42.6) == "43%") // rounds
    }

    @Test("MetricFormat.speed switches units at 1 MB/s")
    func metricFormatSpeed() {
        #expect(MetricFormat.speed(0).hasSuffix("KB/s"))
        #expect(MetricFormat.speed(512).hasSuffix("KB/s"))
        #expect(MetricFormat.speed(5 * 1024 * 1024).hasSuffix("MB/s"))
    }

    @Test("MetricFormat.bytes uses memory units")
    func metricFormatBytes() {
        #expect(MetricFormat.bytes(8 * 1024 * 1024 * 1024).contains("GB"))
    }
}
