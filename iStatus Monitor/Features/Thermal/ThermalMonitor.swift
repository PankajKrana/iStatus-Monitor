import Foundation
import IOKit

actor ThermalMonitor {
    private let smc = SMCConnection()
    /// Temperature key names for this Mac, resolved once process-wide by
    /// `ThermalKeyStore`. Enumerating all ~1500 SMC keys takes ~300ms, so it must
    /// happen exactly once and off the sampling hot path (see `readTemperatures`).
    private var temperatureKeys: [String]?
    /// Guards against launching more than one observer of the shared discovery.
    private var isDiscoveringKeys = false

    func snapshots(every interval: Duration = .seconds(3)) -> AsyncStream<ThermalSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let snapshot = latestSnapshot() {
                        continuation.yield(snapshot)
                    }

                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func latestSnapshot() -> ThermalSnapshot? {
        guard smc.openIfNeeded() else { return nil }

        let fanCount = smc.readInt(key: "FNum", as: .ui8) ?? 0
        var fans: [FanReading] = []

        if fanCount > 0 {
            for index in 0 ..< fanCount {
                let actual = smc.readDouble(key: "F\(index)Ac") ?? 0
                let minRPM = smc.readDouble(key: "F\(index)Mn") ?? 0
                let maxRPM = smc.readDouble(key: "F\(index)Mx") ?? 0
                let pct = maxRPM > 0 ? Swift.min(100, Swift.max(0, (actual / maxRPM) * 100)) : 0
                fans.append(FanReading(index: index, rpm: actual, minRPM: minRPM, maxRPM: maxRPM, percentOfMax: pct))
            }
        }

        // Enumerate every SMC temperature key and aggregate into the zones the
        // UI expects. Chip-agnostic: Intel Macs expose `sp78` keys (TC0P/TG0D…),
        // Apple Silicon exposes many `flt` per-cluster keys (Tc.., Te.., Tg.., TB..).
        // Averaging the per-zone keys yields a representative reading on both,
        // replacing the previous Intel-only hardcoded keys that returned nothing
        // on M-series Macs.
        let temperatures = readTemperatures()
        var sensors: [ThermalSensor] = []
        appendZone(into: &sensors, from: temperatures, prefixes: ["Tp", "Tc", "Te", "TC"], name: "CPU", zone: .cpu)
        appendZone(into: &sensors, from: temperatures, prefixes: ["Tg", "TG"], name: "GPU", zone: .gpu)
        appendZone(into: &sensors, from: temperatures, prefixes: ["TB"], name: "Battery", zone: .battery)
        appendZone(into: &sensors, from: temperatures, prefixes: ["Th", "TH"], name: "Heatsink", zone: .heatsink)
        appendZone(into: &sensors, from: temperatures, prefixes: ["TA", "Ts"], name: "Ambient", zone: .ambient)

        return ThermalSnapshot(
            timestamp: Date(),
            fans: fans,
            sensors: sensors,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    func readPrimaryTemperature() async -> Double? {
        guard let snapshot = latestSnapshot() else { return nil }
        return snapshot.sensors.first(where: { $0.zone == .cpu })?.celsius
    }

    /// Current temperature readings. The first call only schedules a one-time
    /// background enumeration of the SMC key set (~300ms) and returns empty so it
    /// never stalls the shared sampling tick; once discovery completes, every
    /// subsequent sample reads just those cached keys.
    private func readTemperatures() -> [(key: String, celsius: Double)] {
        guard let keys = temperatureKeys else {
            scheduleKeyDiscovery()
            return []
        }
        return keys.compactMap { key in
            guard let value = smc.readDouble(key: key), value > 10, value < 130 else { return nil }
            return (key, value)
        }
    }

    private func scheduleKeyDiscovery() {
        guard !isDiscoveringKeys else { return }
        isDiscoveringKeys = true
        // Resolve via the process-wide store so the ~300ms SMC enumeration runs
        // exactly once for the whole app regardless of how many ThermalMonitors
        // exist, and never blocks a sampling tick.
        Task { [weak self] in
            let keys = await ThermalKeyStore.shared.temperatureKeys()
            await self?.storeDiscoveredKeys(keys)
        }
    }

    private func storeDiscoveredKeys(_ keys: [String]) {
        // Store even an empty result so discovery isn't retried every tick on
        // hardware that exposes no readable temperature keys.
        temperatureKeys = keys
        isDiscoveringKeys = false
    }

    private func appendZone(into sensors: inout [ThermalSensor], from temperatures: [(key: String, celsius: Double)], prefixes: [String], name: String, zone: ThermalZone) {
        let matching = temperatures.filter { temp in prefixes.contains { temp.key.hasPrefix($0) } }
        guard !matching.isEmpty else { return }
        let celsius = matching.map(\.celsius).reduce(0, +) / Double(matching.count)
        let fahrenheit = (celsius * 9.0 / 5.0) + 32.0
        sensors.append(ThermalSensor(key: matching[0].key, name: name, celsius: celsius, fahrenheit: fahrenheit, zone: zone))
    }
}

/// Process-wide resolver for the set of readable SMC temperature keys, which are
/// a static hardware fact. Enumerating the ~1500-key SMC table costs ~300ms, so
/// this actor performs it at most once for the whole process and hands the same
/// result to every `ThermalMonitor`; concurrent callers all await the single
/// in-flight discovery rather than each launching their own SMC scan.
private actor ThermalKeyStore {
    static let shared = ThermalKeyStore()

    private var cachedKeys: [String]?
    private var inFlight: Task<[String], Never>?

    func temperatureKeys() async -> [String] {
        if let cachedKeys { return cachedKeys }
        if let inFlight { return await inFlight.value }

        let task = Task { await Self.enumerate() }
        inFlight = task
        let keys = await task.value
        cachedKeys = keys
        inFlight = nil
        return keys
    }

    /// Runs the ~300ms synchronous SMC enumeration on a GCD background queue
    /// rather than `Task.detached`, so the CPU-bound scan never occupies a Swift
    /// cooperative-pool thread and can't starve the sampling loop's actors.
    private static func enumerate() async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let probe = SMCConnection()
                defer { probe.close() }
                continuation.resume(returning: probe.discoverTemperatureKeys())
            }
        }
    }
}

private enum SMCDataDecoder {
    case flt
    case sp78
    case ui8
    case ui16

    static func from(fourCC: String) -> SMCDataDecoder? {
        switch fourCC {
        case "flt ": return .flt
        case "sp78": return .sp78
        case "ui8 ": return .ui8
        case "ui16": return .ui16
        default: return nil
        }
    }
}

private final class SMCConnection {
    private let selector: UInt32 = 2
    private let commandReadBytes: UInt8 = 5
    private let commandReadIndex: UInt8 = 8
    private let commandReadKeyInfo: UInt8 = 9

    private var connection: io_connect_t = 0
    private var service: io_object_t = 0

    deinit {
        close()
    }

    func openIfNeeded() -> Bool {
        if connection != 0 { return true }

        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        if result != KERN_SUCCESS {
            IOObjectRelease(service)
            service = 0
            connection = 0
            return false
        }

        return true
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }
    }

    func readInt(key: String, as decoder: SMCDataDecoder) -> Int? {
        guard let value = readValue(key: key, requested: decoder) else { return nil }
        return Int(value)
    }

    func readDouble(key: String) -> Double? {
        guard let value = readValue(key: key, requested: nil) else { return nil }
        return value
    }

    /// Enumerates every SMC key once, returning the names of keys that currently
    /// decode to a plausible temperature (begin with "T", 10–130 °C). The caller
    /// caches the result and reads the values directly thereafter.
    func discoverTemperatureKeys() -> [String] {
        guard openIfNeeded(), let count = readKeyCount() else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(64)
        for index in 0 ..< count {
            guard let key = keyName(at: index), key.hasPrefix("T") else { continue }
            guard let value = readDouble(key: key), value > 10, value < 130 else { continue }
            keys.append(key)
        }
        return keys
    }

    /// Total number of SMC keys, read from the special `#KEY` key (big-endian u32).
    private func readKeyCount() -> Int? {
        var infoInput = SMCKeyData()
        infoInput.key = fourCCToUInt32("#KEY")
        infoInput.data8 = commandReadKeyInfo
        guard let infoOutput = callStructMethod(input: infoInput) else { return nil }

        var readInput = SMCKeyData()
        readInput.key = fourCCToUInt32("#KEY")
        readInput.keyInfo = infoOutput.keyInfo
        readInput.data8 = commandReadBytes
        guard let readOutput = callStructMethod(input: readInput) else { return nil }

        let bytes = tupleToArray(readOutput.bytes)
        guard bytes.count >= 4 else { return nil }
        return (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
    }

    /// The four-character key name at a given enumeration index.
    private func keyName(at index: Int) -> String? {
        var input = SMCKeyData()
        input.data8 = commandReadIndex
        input.data32 = UInt32(index)
        guard let output = callStructMethod(input: input), output.key != 0 else { return nil }
        return uint32ToFourCC(output.key)
    }

    private func readValue(key: String, requested: SMCDataDecoder?) -> Double? {
        guard openIfNeeded(), key.count == 4 else { return nil }

        let keyCode = fourCCToUInt32(key)

        // Step 1: Ask AppleSMC for metadata (data size + data type) for the key.
        var keyInfoInput = SMCKeyData()
        keyInfoInput.key = keyCode
        keyInfoInput.data8 = commandReadKeyInfo

        guard let keyInfoOutput = callStructMethod(input: keyInfoInput) else { return nil }

        // Step 2: Read the raw payload bytes for that key using the returned metadata.
        var readInput = SMCKeyData()
        readInput.key = keyCode
        readInput.keyInfo.dataSize = keyInfoOutput.keyInfo.dataSize
        readInput.keyInfo.dataType = keyInfoOutput.keyInfo.dataType
        readInput.data8 = commandReadBytes

        guard let readOutput = callStructMethod(input: readInput) else { return nil }

        let rawBytes = tupleToArray(readOutput.bytes)
        // Use the size/type from the key-info probe: on Apple Silicon the read
        // response leaves keyInfo zeroed, so reading dataSize back from it yields
        // 0 and discards the payload.
        let size = Int(keyInfoOutput.keyInfo.dataSize)
        guard size > 0, size <= rawBytes.count else { return nil }

        let dataType = uint32ToFourCC(keyInfoOutput.keyInfo.dataType)
        let decoder = requested ?? SMCDataDecoder.from(fourCC: dataType)

        guard let decoder else { return nil }
        return decode(bytes: Array(rawBytes.prefix(size)), as: decoder)
    }

    private func callStructMethod(input: SMCKeyData) -> SMCKeyData? {
        var localInput = input
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride

        // AppleSMC user client selector 2 accepts/returns a packed SMCKeyData structure.
        let result = withUnsafePointer(to: &localInput) { inputPtr in
            withUnsafeMutablePointer(to: &output) { outputPtr in
                IOConnectCallStructMethod(
                    connection,
                    selector,
                    inputPtr,
                    MemoryLayout<SMCKeyData>.stride,
                    outputPtr,
                    &outputSize
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return output
    }

    private func decode(bytes: [UInt8], as decoder: SMCDataDecoder) -> Double? {
        switch decoder {
        case .ui8:
            guard let first = bytes.first else { return nil }
            return Double(first)

        case .ui16:
            guard bytes.count >= 2 else { return nil }
            let value = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(value)

        case .sp78:
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256.0

        case .flt:
            guard bytes.count >= 4 else { return nil }
            // SMC `flt ` payloads are little-endian IEEE-754 on Apple platforms
            // (verified against live AppleSilicon sensors); assembling them
            // big-endian produced garbage, so these keys were always discarded.
            let value = (UInt32(bytes[3]) << 24)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[1]) << 8)
                | UInt32(bytes[0])
            return Double(Float(bitPattern: value))
        }
    }

    private func fourCCToUInt32(_ key: String) -> UInt32 {
        let scalars = Array(key.utf8)
        return (UInt32(scalars[0]) << 24)
            | (UInt32(scalars[1]) << 16)
            | (UInt32(scalars[2]) << 8)
            | UInt32(scalars[3])
    }

    private func uint32ToFourCC(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    private func tupleToArray(_ tuple: SMCBytes) -> [UInt8] {
        withUnsafeBytes(of: tuple) { Array($0) }
    }
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers: SMCVersion = .init()
    var pLimitData: SMCPLimitData = .init()
    var keyInfo: SMCKeyInfoData = .init()
    // The AppleSMC user client expects an exactly-80-byte parameter struct.
    // Without this 2-byte pad Swift lays the struct out at 76 bytes and every
    // IOConnectCallStructMethod call is rejected with kIOReturnBadArgument —
    // which is why SMC reads (temperatures, fans) silently returned nothing.
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
