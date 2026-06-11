import Foundation
import IOKit
import IOKit.ps

actor BatteryMonitor {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let healthHistoryKey = "battery.health.history"
    private let chargeHistoryKey = "battery.charge.history"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshots(every interval: Duration = .seconds(15)) -> AsyncStream<BatterySnapshot?> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let snapshot = latestSnapshot()
                    continuation.yield(snapshot)
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

    func latestSnapshot() -> BatterySnapshot? {
        // Looks up the AppleSmartBattery service in the I/O Registry for low-level battery telemetry.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS,
              let raw = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        // Raw mAh capacities — the values that are actually in milliamp-hours.
        // On modern macOS `MaxCapacity`/`CurrentCapacity` are a *percentage* pair
        // (MaxCapacity == 100), so health must use AppleRaw*Capacity, not them,
        // and `DesignCycleCount9C` is a cycle rating — never a capacity.
        let rawCurrent = value(raw, keys: ["AppleRawCurrentCapacity"]) ?? 0
        let rawMax = value(raw, keys: ["AppleRawMaxCapacity", "NominalChargeCapacity"]) ?? rawCurrent
        let design = value(raw, keys: ["DesignCapacity"]) ?? rawMax
        let cycleCount = value(raw, keys: ["CycleCount"]) ?? 0
        let voltage = value(raw, keys: ["Voltage"]) ?? 0
        let amperage = value(raw, keys: ["Amperage"]) ?? 0
        let temperatureRaw = value(raw, keys: ["Temperature"]) ?? 0

        // Charge %: prefer the high-level IOPS reading; otherwise use the
        // CurrentCapacity/MaxCapacity percentage pair when present, else the raw
        // mAh ratio. Never divide a percentage by a mAh capacity.
        let maxPercentPair = value(raw, keys: ["MaxCapacity"]) ?? 0
        let smartChargePercent: Double?
        if let currentPercent = value(raw, keys: ["CurrentCapacity"]), maxPercentPair > 0, maxPercentPair <= 100 {
            smartChargePercent = (Double(currentPercent) / Double(maxPercentPair)) * 100
        } else if rawMax > 0 {
            smartChargePercent = (Double(rawCurrent) / Double(rawMax)) * 100
        } else {
            smartChargePercent = nil
        }
        let fallbackLevel = readChargePercentFallback()
        let chargePercent = fallbackLevel ?? smartChargePercent ?? 0

        let isCharging = (raw["IsCharging"] as? Bool) ?? false
        let isCharged = (raw["FullyCharged"] as? Bool) ?? false
        let externalConnected = (raw["ExternalConnected"] as? Bool) ?? false

        let chargeState: BatteryChargeState
        if isCharged {
            chargeState = .full
        } else if isCharging {
            chargeState = .charging
        } else if externalConnected {
            chargeState = .ac
        } else {
            chargeState = .discharging
        }

        let timeToEmpty = value(raw, keys: ["AvgTimeToEmpty", "TimeRemaining"])
        let timeToFull = value(raw, keys: ["AvgTimeToFull"])

        let tempC = Double(temperatureRaw) / 100.0
        let tempF = (tempC * 9.0 / 5.0) + 32.0

        let watts = (Double(voltage) / 1000.0) * (Double(amperage) / 1000.0)
        // Health = full-charge capacity (AppleRawMaxCapacity, mAh) / design
        // capacity (mAh). Both are genuine mAh values.
        let healthPercent = design > 0 ? max(0, min(100, (Double(rawMax) / Double(design)) * 100.0)) : 0

        let serial = (raw["BatterySerialNumber"] as? String) ?? (raw["Serial"] as? String) ?? "Unknown"
        let now = Date()

        let healthHistory = updatedHealthHistory(now: now, cycleCount: cycleCount, healthPercent: healthPercent)
        let chargeHistory = updatedChargeHistory(now: now, chargePercent: chargePercent)

        return BatterySnapshot(
            timestamp: now,
            currentCapacitymAh: rawCurrent,
            designCapacitymAh: design,
            healthPercent: healthPercent,
            cycleCount: cycleCount,
            chargeState: chargeState,
            chargePercent: chargePercent,
            timeToEmptyMinutes: positiveMinutes(timeToEmpty),
            timeToFullMinutes: positiveMinutes(timeToFull),
            voltageMillivolts: voltage,
            amperageMilliamps: amperage,
            watts: watts,
            temperatureCelsius: tempC,
            temperatureFahrenheit: tempF,
            serialNumber: serial,
            chargeHistory24h: chargeHistory,
            healthHistory: healthHistory
        )
    }

    func read() async -> BatteryMetrics {
        guard let snapshot = latestSnapshot() else { return .empty }
        return BatteryMetrics(
            levelPercent: snapshot.chargePercent,
            isCharging: snapshot.chargeState == .charging || snapshot.chargeState == .full,
            cycleCount: snapshot.cycleCount
        )
    }

    private func readChargePercentFallback() -> Double? {
        // Uses IOPS as a higher-level power source API fallback when AppleSmartBattery keys are absent.
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let current = description[kIOPSCurrentCapacityKey as String] as? Int,
               let max = description[kIOPSMaxCapacityKey as String] as? Int,
               max > 0 {
                return (Double(current) / Double(max)) * 100
            }
        }

        return nil
    }

    private func updatedHealthHistory(now: Date, cycleCount: Int, healthPercent: Double) -> [BatteryHistoryPoint] {
        var history = loadHistory(BatteryHistoryPoint.self, key: healthHistoryKey)
        if let last = history.last,
           abs(last.timestamp.timeIntervalSince(now)) < 1800,
           last.cycleCount == cycleCount,
           abs(last.healthPercent - healthPercent) < 0.01 {
            return history
        }

        history.append(BatteryHistoryPoint(timestamp: now, cycleCount: cycleCount, healthPercent: healthPercent))
        history = history.suffix(720).map { $0 }
        saveHistory(history, key: healthHistoryKey)
        return history
    }

    private func updatedChargeHistory(now: Date, chargePercent: Double) -> [BatteryChargePoint] {
        var history = loadHistory(BatteryChargePoint.self, key: chargeHistoryKey)
        history.append(BatteryChargePoint(timestamp: now, chargePercent: chargePercent))
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        history = history.filter { $0.timestamp >= cutoff }
        saveHistory(history, key: chargeHistoryKey)
        return history
    }

    private func loadHistory<T: Decodable>(_ type: T.Type, key: String) -> [T] {
        guard let data = defaults.data(forKey: key),
              let history = try? decoder.decode([T].self, from: data) else {
            return []
        }
        return history
    }

    private func saveHistory<T: Encodable>(_ history: [T], key: String) {
        guard let data = try? encoder.encode(history) else { return }
        defaults.set(data, forKey: key)
    }

    private func value(_ dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let intValue = dictionary[key] as? Int { return intValue }
            if let number = dictionary[key] as? NSNumber { return number.intValue }
        }
        return nil
    }

    private func positiveMinutes(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }
}
