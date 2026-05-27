import Foundation

actor BatteryMonitor {
    func read() async -> BatteryMetrics {
        // macOS desktop Macs may not have battery data.
        let hasBattery = Bool.random()
        if hasBattery {
            return BatteryMetrics(levelPercent: Double.random(in: 20 ... 100), isCharging: Bool.random(), cycleCount: Int.random(in: 50 ... 900))
        } else {
            return .empty
        }
    }
}
