import Foundation
import IOKit

actor ThermalMonitor {
    private let smc = SMCConnection()

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

        var sensors: [ThermalSensor] = []
        appendSensor(into: &sensors, keyCandidates: ["TC0P", "TC0C"], name: "CPU", zone: .cpu)
        appendSensor(into: &sensors, keyCandidates: ["TG0D", "TG0P"], name: "GPU", zone: .gpu)
        appendSensor(into: &sensors, keyCandidates: ["TB0T"], name: "Battery", zone: .battery)
        appendSensor(into: &sensors, keyCandidates: ["Th0H"], name: "Heatsink", zone: .heatsink)
        appendSensor(into: &sensors, keyCandidates: ["TA0P"], name: "Ambient", zone: .ambient)

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

    private func appendSensor(into sensors: inout [ThermalSensor], keyCandidates: [String], name: String, zone: ThermalZone) {
        for key in keyCandidates {
            if let celsius = smc.readDouble(key: key) {
                let fahrenheit = (celsius * 9.0 / 5.0) + 32.0
                sensors.append(ThermalSensor(key: key, name: name, celsius: celsius, fahrenheit: fahrenheit, zone: zone))
                return
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
        let size = Int(readOutput.keyInfo.dataSize)
        guard size > 0, size <= rawBytes.count else { return nil }

        let dataType = uint32ToFourCC(readOutput.keyInfo.dataType)
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
            let value = (UInt32(bytes[0]) << 24)
                | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8)
                | UInt32(bytes[3])
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
