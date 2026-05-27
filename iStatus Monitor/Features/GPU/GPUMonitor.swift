import Foundation

actor GPUMonitor {
    func read() async -> GPUMetrics {
        GPUMetrics(usagePercent: Double.random(in: 5 ... 95), temperatureCelsius: nil)
    }
}
