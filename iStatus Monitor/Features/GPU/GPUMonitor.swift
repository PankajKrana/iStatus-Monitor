import CoreGraphics
import Foundation
import IOKit
import Metal

actor GPUMonitor {
    func snapshots(every interval: Duration = .seconds(2)) -> AsyncStream<GPUSnapshot> {
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

    func latestSnapshot() -> GPUSnapshot? {
        let gpus = iokitGPUStats().mergingWithMetal(metalGPUStats())
        let displays = displayInfos()

        return GPUSnapshot(timestamp: Date(), gpus: gpus, displays: displays)
    }

    func read() async -> GPUMetrics {
        guard let snapshot = latestSnapshot(), !snapshot.gpus.isEmpty else {
            return .empty
        }

        let avgUtil = snapshot.gpus.map(\.utilizationPercent).reduce(0, +) / Double(snapshot.gpus.count)
        let temp = snapshot.gpus.compactMap(\.temperatureCelsius).first
        return GPUMetrics(usagePercent: avgUtil, temperatureCelsius: temp)
    }

    private func iokitGPUStats() -> [GPUStats] {
        var result: [GPUStats] = []

        result.append(contentsOf: scanService(className: "IOPCIDevice"))
        result.append(contentsOf: scanService(className: "AGPMController"))
        // Apple Silicon GPUs expose utilization under the IOAccelerator /
        // AGXAccelerator service (PerformanceStatistics → "Device Utilization %"),
        // never under IOPCIDevice — without this, util was always 0 on M-series.
        result.append(contentsOf: scanService(className: "IOAccelerator"))

        // Collapse entries describing the same GPU (e.g. an IOAccelerator nub and
        // a Metal device, or duplicate accelerator nubs) by name, merging so the
        // entry that actually carries utilization / VRAM wins.
        var dedup: [String: GPUStats] = [:]
        for gpu in result where shouldKeep(gpu: gpu) {
            let key = gpu.name.lowercased()
            if let existing = dedup[key] {
                dedup[key] = merge(existing, gpu)
            } else {
                dedup[key] = gpu
            }
        }

        return Array(dedup.values).sorted { $0.name < $1.name }
    }

    private func merge(_ a: GPUStats, _ b: GPUStats) -> GPUStats {
        GPUStats(
            id: a.id,
            name: a.name,
            vendor: a.vendor != "Unknown" ? a.vendor : b.vendor,
            utilizationPercent: max(a.utilizationPercent, b.utilizationPercent),
            vramTotalMB: a.vramTotalMB ?? b.vramTotalMB,
            vramUsedMB: a.vramUsedMB ?? b.vramUsedMB,
            temperatureCelsius: a.temperatureCelsius ?? b.temperatureCelsius,
            metalDeviceName: a.metalDeviceName ?? b.metalDeviceName,
            isLowPower: a.isLowPower ?? b.isLowPower,
            isRemovable: a.isRemovable ?? b.isRemovable,
            recommendedMaxWorkingSetSize: a.recommendedMaxWorkingSetSize ?? b.recommendedMaxWorkingSetSize,
            isIntegrated: a.isIntegrated || b.isIntegrated
        )
    }

    private func scanService(className: String) -> [GPUStats] {
        var iterator: io_iterator_t = 0
        let match = IOServiceMatching(className)
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator)
        guard status == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var output: [GPUStats] = []

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            guard let properties = createProperties(for: service) else { continue }

            let model = stringValue(properties, keys: ["model", "IOName", "IOClass"])
            let vendorID = intValue(properties, keys: ["vendor-id", "vendorID"])
            let vendorName = vendorFrom(vendorID: vendorID, fallback: model)

            let perf = properties["PerformanceStatistics"] as? [String: Any]
            // Apple Silicon reports "%"-suffixed keys ("Device/Renderer/Tiler
            // Utilization %"); Intel/AMD use the unsuffixed names. Prefer the
            // single overall "Device Utilization %" when present.
            let deviceUtil = doubleValue(perf, keys: ["Device Utilization %", "GPU Activity(%)"])
            let rendererUtil = doubleValue(perf, keys: ["Renderer Utilization %", "Renderer Utilization", "GPU Core Utilization"])
            let tilerUtil = doubleValue(perf, keys: ["Tiler Utilization %", "Tiler Utilization"])
            let util: Double
            if let deviceUtil {
                util = max(0, min(100, deviceUtil))
            } else if let rendererUtil, let tilerUtil {
                util = max(0, min(100, (rendererUtil + tilerUtil) / 2))
            } else {
                util = max(0, min(100, rendererUtil ?? tilerUtil ?? 0))
            }

            let vramTotal = intValue(properties, keys: ["VRAM,totalMB", "vram-total-mb", "VRAM Total"])
            let vramUsed = intValue(perf, keys: ["VRAM Used", "In Use VidMem", "vramUsedBytes", "In use system memory"]).map { raw in
                if raw > 1024 * 1024 { return raw / (1024 * 1024) }
                return raw
            }

            let temp = doubleValue(perf, keys: ["Temperature(C)", "Temperature", "GPU die temperature"]).map { value in
                if value > 200 { return value / 100.0 }
                return value
            }

            let integrated = boolValue(properties, keys: ["built-in", "Integrated"]) ?? (vramTotal == nil)
            let name = model ?? "Unknown GPU"
            let gpuID = "\(className)-\(service)"

            output.append(
                GPUStats(
                    id: gpuID,
                    name: name,
                    vendor: vendorName,
                    utilizationPercent: util,
                    vramTotalMB: vramTotal,
                    vramUsedMB: vramUsed,
                    temperatureCelsius: temp,
                    metalDeviceName: nil,
                    isLowPower: nil,
                    isRemovable: nil,
                    recommendedMaxWorkingSetSize: nil,
                    isIntegrated: integrated
                )
            )
        }

        return output
    }

    private func metalGPUStats() -> [GPUStats] {
        let devices = MTLCopyAllDevices()
        guard !devices.isEmpty else {
            if let defaultDevice = MTLCreateSystemDefaultDevice() {
                return [gpuStat(from: defaultDevice)]
            }
            return []
        }
        return devices.map(gpuStat(from:))
    }

    private func gpuStat(from device: MTLDevice) -> GPUStats {
        GPUStats(
            id: "metal-\(device.registryID)",
            name: device.name,
            vendor: vendorFrom(deviceName: device.name),
            utilizationPercent: 0,
            vramTotalMB: nil,
            vramUsedMB: nil,
            temperatureCelsius: nil,
            metalDeviceName: device.name,
            isLowPower: device.isLowPower,
            isRemovable: device.isRemovable,
            recommendedMaxWorkingSetSize: device.recommendedMaxWorkingSetSize,
            isIntegrated: device.isLowPower && !device.isRemovable
        )
    }

    private func displayInfos() -> [DisplayInfo] {
        var maxDisplays: UInt32 = 16
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        let status = CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount)
        guard status == .success else { return [] }

        if displayCount > maxDisplays {
            maxDisplays = displayCount
            activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
            let secondStatus = CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount)
            guard secondStatus == .success else { return [] }
        }

        return activeDisplays.prefix(Int(displayCount)).map { id in
            let bounds = CGDisplayBounds(id)
            let mode = CGDisplayCopyDisplayMode(id)
            let refresh = mode?.refreshRate ?? 0
            let isMain = CGMainDisplayID() == id
            let isRetina = (mode?.pixelWidth ?? Int(bounds.width)) > Int(bounds.width)

            let colorSpaceName: String
            let cs = CGDisplayCopyColorSpace(id)
            if let name = cs.name as String? {
                colorSpaceName = name
            } else {
                colorSpaceName = "Unknown"
            }

            return DisplayInfo(
                id: id,
                width: Int(bounds.width),
                height: Int(bounds.height),
                refreshRate: refresh,
                isMain: isMain,
                isRetina: isRetina,
                colorSpaceName: colorSpaceName
            )
        }
    }

    private func createProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func shouldKeep(gpu: GPUStats) -> Bool {
        if gpu.name.localizedCaseInsensitiveContains("display") { return false }
        if gpu.name.localizedCaseInsensitiveContains("audio") { return false }
        return gpu.vendor != "Unknown" || gpu.utilizationPercent > 0 || gpu.vramTotalMB != nil
    }

    private func vendorFrom(vendorID: Int?, fallback: String?) -> String {
        if let vendorID {
            switch vendorID {
            case 0x1002: return "AMD"
            case 0x10DE: return "NVIDIA"
            case 0x8086: return "Intel"
            case 0x106B: return "Apple"
            default: break
            }
        }
        return vendorFrom(deviceName: fallback ?? "")
    }

    private func vendorFrom(deviceName: String) -> String {
        let lowercase = deviceName.lowercased()
        if lowercase.contains("amd") || lowercase.contains("radeon") { return "AMD" }
        if lowercase.contains("nvidia") || lowercase.contains("geforce") { return "NVIDIA" }
        if lowercase.contains("apple") { return "Apple" }
        if lowercase.contains("intel") { return "Intel" }
        return "Unknown"
    }

    private func stringValue(_ dictionary: [String: Any]?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String { return value }
            if let value = dictionary[key] as? Data, let text = String(data: value, encoding: .utf8) {
                return text.trimmingCharacters(in: .controlCharacters)
            }
        }
        return nil
    }

    private func intValue(_ dictionary: [String: Any]?, keys: [String]) -> Int? {
        guard let dictionary else { return nil }
        for key in keys {
            if let intValue = dictionary[key] as? Int { return intValue }
            if let number = dictionary[key] as? NSNumber { return number.intValue }
            if let data = dictionary[key] as? Data {
                if data.count >= 4 {
                    return data.withUnsafeBytes { rawBuffer in
                        rawBuffer.load(as: UInt32.self)
                    }.littleEndian.intValue
                }
            }
        }
        return nil
    }

    private func doubleValue(_ dictionary: [String: Any]?, keys: [String]) -> Double? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? Double { return value }
            if let value = dictionary[key] as? NSNumber { return value.doubleValue }
        }
        return nil
    }

    private func boolValue(_ dictionary: [String: Any]?, keys: [String]) -> Bool? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? Bool { return value }
            if let value = dictionary[key] as? NSNumber { return value.boolValue }
        }
        return nil
    }
}

private extension FixedWidthInteger {
    var intValue: Int {
        Int(truncatingIfNeeded: self)
    }
}

private extension Array where Element == GPUStats {
    func mergingWithMetal(_ metalStats: [GPUStats]) -> [GPUStats] {
        guard !metalStats.isEmpty else { return self }
        if isEmpty { return metalStats }

        var merged = self

        for metal in metalStats {
            if let idx = merged.firstIndex(where: { $0.name == metal.name || $0.vendor == metal.vendor && $0.isIntegrated == metal.isIntegrated }) {
                let existing = merged[idx]
                merged[idx] = GPUStats(
                    id: existing.id,
                    name: existing.name,
                    vendor: existing.vendor,
                    utilizationPercent: existing.utilizationPercent,
                    vramTotalMB: existing.vramTotalMB,
                    vramUsedMB: existing.vramUsedMB,
                    temperatureCelsius: existing.temperatureCelsius,
                    metalDeviceName: metal.metalDeviceName,
                    isLowPower: metal.isLowPower,
                    isRemovable: metal.isRemovable,
                    recommendedMaxWorkingSetSize: metal.recommendedMaxWorkingSetSize,
                    isIntegrated: existing.isIntegrated || metal.isIntegrated
                )
            } else {
                merged.append(metal)
            }
        }

        return merged
    }
}
