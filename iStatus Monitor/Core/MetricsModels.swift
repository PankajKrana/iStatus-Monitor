import Foundation

struct CoreUsage: Codable, Sendable, Equatable {
    let coreIndex: Int
    let user: Float
    let system: Float
    let idle: Float
    let nice: Float

    var active: Float {
        max(0, min(1, user + system + nice))
    }
}

struct LoadAverage: Codable, Sendable, Equatable {
    let one: Double
    let five: Double
    let fifteen: Double
}

struct CPUSnapshot: Codable, Sendable, Equatable {
    let timestamp: Date
    let perCoreUsage: [CoreUsage]
    let overallLoad: Float
    let loadAverage: LoadAverage
}

enum MemoryPressureLevel: String, Codable, Sendable {
    case normal
    case warning
    case critical
}

struct MemorySnapshot: Codable, Sendable, Equatable {
    let timestamp: Date
    let totalBytes: UInt64
    let usedBytes: UInt64
    let wiredBytes: UInt64
    let appBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let freeBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64
    let pressure: MemoryPressureLevel

    var usedString: String { Int(usedBytes).toMemoryString() }
    var wiredString: String { Int(wiredBytes).toMemoryString() }
    var appString: String { Int(appBytes).toMemoryString() }
    var compressedString: String { Int(compressedBytes).toMemoryString() }
    var cachedString: String { Int(cachedBytes).toMemoryString() }
    var freeString: String { Int(freeBytes).toMemoryString() }
    var swapUsedString: String { Int(swapUsedBytes).toMemoryString() }
    var swapTotalString: String { Int(swapTotalBytes).toMemoryString() }

    var usedRatio: Float {
        guard totalBytes > 0 else { return 0 }
        return max(0, min(1, Float(usedBytes) / Float(totalBytes)))
    }
}

struct CPUMetrics: Codable, Sendable {
    var usagePercent: Double
    var coreCount: Int
    var temperatureCelsius: Double?

    static let empty = CPUMetrics(usagePercent: 0, coreCount: 0, temperatureCelsius: nil)
}

struct RAMMetrics: Codable, Sendable {
    var usedBytes: UInt64
    var totalBytes: UInt64

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return (Double(usedBytes) / Double(totalBytes)) * 100
    }

    static let empty = RAMMetrics(usedBytes: 0, totalBytes: 0)
}

struct BatteryMetrics: Codable, Sendable {
    var levelPercent: Double
    var isCharging: Bool
    var cycleCount: Int?

    static let empty = BatteryMetrics(levelPercent: 0, isCharging: false, cycleCount: nil)
}

struct NetworkMetrics: Codable, Sendable {
    var bytesInPerSecond: UInt64
    var bytesOutPerSecond: UInt64
    var primaryInterface: String

    static let empty = NetworkMetrics(bytesInPerSecond: 0, bytesOutPerSecond: 0, primaryInterface: "en0")
}

struct GPUMetrics: Codable, Sendable {
    var usagePercent: Double
    var temperatureCelsius: Double?

    static let empty = GPUMetrics(usagePercent: 0, temperatureCelsius: nil)
}

struct SystemSnapshot: Codable, Sendable {
    var timestamp: Date
    var cpu: CPUMetrics
    var cpuSnapshot: CPUSnapshot?
    var ram: RAMMetrics
    var memorySnapshot: MemorySnapshot?
    var battery: BatteryMetrics
    var network: NetworkMetrics
    var gpu: GPUMetrics
}
