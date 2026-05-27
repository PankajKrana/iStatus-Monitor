import Foundation

actor NetworkMonitor {
    func read() async -> NetworkMetrics {
        let inbound = UInt64.random(in: 20_000 ... 2_000_000)
        let outbound = UInt64.random(in: 10_000 ... 1_200_000)
        return NetworkMetrics(bytesInPerSecond: inbound, bytesOutPerSecond: outbound, primaryInterface: "en0")
    }
}
