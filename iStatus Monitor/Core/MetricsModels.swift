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

enum BatteryChargeState: String, Codable, Sendable {
    case charging
    case discharging
    case full
    case ac
    case unknown
}

struct BatteryHistoryPoint: Codable, Sendable, Equatable, Identifiable {
    let timestamp: Date
    let cycleCount: Int
    let healthPercent: Double

    var id: Date { timestamp }
}

struct BatteryChargePoint: Codable, Sendable, Equatable, Identifiable {
    let timestamp: Date
    let chargePercent: Double

    var id: Date { timestamp }
}

struct BatterySnapshot: Codable, Sendable, Equatable {
    let timestamp: Date
    let currentCapacitymAh: Int
    let designCapacitymAh: Int
    let healthPercent: Double
    let cycleCount: Int
    let chargeState: BatteryChargeState
    let chargePercent: Double
    let timeToEmptyMinutes: Int?
    let timeToFullMinutes: Int?
    let voltageMillivolts: Int
    let amperageMilliamps: Int
    let watts: Double
    let temperatureCelsius: Double
    let temperatureFahrenheit: Double
    let serialNumber: String
    let chargeHistory24h: [BatteryChargePoint]
    let healthHistory: [BatteryHistoryPoint]

    var currentCapacityString: String { "\(currentCapacitymAh) mAh" }
    var designCapacityString: String { "\(designCapacitymAh) mAh" }
    var wattsString: String { String(format: "%.2f W", watts) }
    var temperatureCString: String { String(format: "%.1f °C", temperatureCelsius) }
    var temperatureFString: String { String(format: "%.1f °F", temperatureFahrenheit) }
}

enum NetworkInterfaceType: String, Codable, Sendable {
    case wifi
    case ethernet
    case vpn
    case cellular
    case other
}

struct InterfaceStats: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let displayName: String
    let type: NetworkInterfaceType
    let downloadBytesPerSecond: UInt64
    let uploadBytesPerSecond: UInt64
    let totalBytesReceived: UInt64
    let totalBytesSent: UInt64
    let ipv4Address: String?
    let ipv6Address: String?
    let isConnected: Bool
    let isPrimary: Bool

    var id: String { name }
}

struct ThroughputPoint: Codable, Sendable, Equatable, Identifiable {
    let timestamp: Date
    let downloadBytesPerSecond: UInt64
    let uploadBytesPerSecond: UInt64

    var id: Date { timestamp }
}

struct NetworkSnapshot: Codable, Sendable, Equatable {
    let timestamp: Date
    let interfaces: [InterfaceStats]
    let connectivitySatisfied: Bool
    let totalDownloadSinceLaunch: UInt64
    let totalUploadSinceLaunch: UInt64
    let history60s: [ThroughputPoint]
}

struct DiskVolume: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let mountPoint: String
    let totalBytes: UInt64
    let freeBytes: UInt64
    let isRemovable: Bool
    let isInternal: Bool

    var id: String { mountPoint }

    var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }

    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    var usedPercent: Double { usedRatio * 100 }

    var totalString: String { ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file) }
    var usedString: String { ByteCountFormatter.string(fromByteCount: Int64(usedBytes), countStyle: .file) }
    var freeString: String { ByteCountFormatter.string(fromByteCount: Int64(freeBytes), countStyle: .file) }
}

struct DiskActivityPoint: Codable, Sendable, Equatable, Identifiable {
    let timestamp: Date
    let readBytesPerSecond: UInt64
    let writeBytesPerSecond: UInt64

    var id: Date { timestamp }
}

struct DiskSnapshot: Codable, Sendable, Equatable {
    let timestamp: Date
    let volumes: [DiskVolume]
    let readBytesPerSecond: UInt64
    let writeBytesPerSecond: UInt64
    let history60s: [DiskActivityPoint]

    /// The boot/root volume, falling back to the largest internal volume, then any volume.
    var primaryVolume: DiskVolume? {
        volumes.first(where: { $0.mountPoint == "/" })
            ?? volumes.filter { $0.isInternal && !$0.isRemovable }.max(by: { $0.totalBytes < $1.totalBytes })
            ?? volumes.first
    }
}

struct GPUStats: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let vendor: String
    let utilizationPercent: Double
    let vramTotalMB: Int?
    let vramUsedMB: Int?
    let temperatureCelsius: Double?
    let metalDeviceName: String?
    let isLowPower: Bool?
    let isRemovable: Bool?
    let recommendedMaxWorkingSetSize: UInt64?
    let isIntegrated: Bool
}

struct DisplayInfo: Codable, Sendable, Equatable, Identifiable {
    let id: UInt32
    let width: Int
    let height: Int
    let refreshRate: Double
    let isMain: Bool
    let isRetina: Bool
    let colorSpaceName: String
}

struct GPUSnapshot: Codable, Sendable, Equatable {
    let timestamp: Date
    let gpus: [GPUStats]
    let displays: [DisplayInfo]
}

enum ThermalZone: String, Codable, Sendable, CaseIterable {
    case cpu
    case gpu
    case battery
    case heatsink
    case ambient
}

struct FanReading: Codable, Sendable, Equatable, Identifiable {
    let index: Int
    let rpm: Double
    let minRPM: Double
    let maxRPM: Double
    let percentOfMax: Double

    var id: Int { index }
}

struct ThermalSensor: Codable, Sendable, Equatable, Identifiable {
    let key: String
    let name: String
    let celsius: Double
    let fahrenheit: Double
    let zone: ThermalZone

    var id: String { key }
}

struct ThermalSnapshot: Sendable, Equatable, Codable {
    let timestamp: Date
    let fans: [FanReading]
    let sensors: [ThermalSensor]
    let thermalState: ProcessInfo.ThermalState

    enum CodingKeys: String, CodingKey {
        case timestamp
        case fans
        case sensors
        case thermalStateRaw
    }

    init(timestamp: Date, fans: [FanReading], sensors: [ThermalSensor], thermalState: ProcessInfo.ThermalState) {
        self.timestamp = timestamp
        self.fans = fans
        self.sensors = sensors
        self.thermalState = thermalState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        fans = try container.decode([FanReading].self, forKey: .fans)
        sensors = try container.decode([ThermalSensor].self, forKey: .sensors)
        let raw = try container.decode(Int.self, forKey: .thermalStateRaw)
        thermalState = ProcessInfo.ThermalState(rawValue: raw) ?? .nominal
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(fans, forKey: .fans)
        try container.encode(sensors, forKey: .sensors)
        try container.encode(thermalState.rawValue, forKey: .thermalStateRaw)
    }
}

struct CPUMetrics: Codable, Sendable {
    var usagePercent: Double
    var coreCount: Int
    var temperatureCelsius: Double?

    static let empty = CPUMetrics(usagePercent: 0, coreCount: 0, temperatureCelsius: nil)
}

struct MemoryMetrics: Codable, Sendable {
    var usedBytes: UInt64
    var totalBytes: UInt64

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return (Double(usedBytes) / Double(totalBytes)) * 100
    }

    static let empty = MemoryMetrics(usedBytes: 0, totalBytes: 0)
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

struct DiskMetrics: Codable, Sendable {
    var usedPercent: Double
    var usedBytes: UInt64
    var totalBytes: UInt64
    var readBytesPerSecond: UInt64
    var writeBytesPerSecond: UInt64

    static let empty = DiskMetrics(usedPercent: 0, usedBytes: 0, totalBytes: 0, readBytesPerSecond: 0, writeBytesPerSecond: 0)
}

struct SystemSnapshot: Codable, Sendable {
    var timestamp: Date
    var cpu: CPUMetrics
    var cpuSnapshot: CPUSnapshot?
    var ram: MemoryMetrics
    var memorySnapshot: MemorySnapshot?
    var battery: BatteryMetrics
    var batterySnapshot: BatterySnapshot?
    var network: NetworkMetrics
    var networkSnapshot: NetworkSnapshot?
    var gpu: GPUMetrics
    var gpuSnapshot: GPUSnapshot?
    var disk: DiskMetrics
    var diskSnapshot: DiskSnapshot?
    var thermalSnapshot: ThermalSnapshot?
}
